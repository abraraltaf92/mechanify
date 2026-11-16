import AudioToolbox
import AVFoundation

/// Low-latency click playback.
///
/// - Every press and release sample of a profile is decoded and converted once, with the
///   highest-quality sample-rate converter, to 48 kHz mono, then cached for the life of
///   the app. Nothing is decoded or converted while you type, and switching back to a
///   profile is instant.
/// - Clicks are mixed by `VoiceMixer` inside a single `AVAudioSourceNode`: a click starts
///   at the first sample of the next output slice (≤ 2.7 ms with a 128-frame buffer),
///   up to 32 overlap, and the render thread never allocates or waits.
/// - Each click is placed where the key sits on the keyboard, with equal-power gains
///   applied to its own samples, so the position is exact from the first sample.
/// - The output device is asked for a small I/O buffer to keep latency down.
///
/// `handle(_:)` is safe to call from the key listener's thread; settings and `load`
/// can be called from the main thread.
public final class SoundEngine {
    /// Requested output buffer. 128 frames is ~2.7 ms at 48 kHz; the device may round it.
    public static let preferredIOBufferFrames: UInt32 = 128
    /// The format clips are stored in and voices are mixed at.
    public static let internalFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    static let mixFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    private struct ClipBank {
        let presses: [Clip]
        let releases: [Clip]
    }

    private let engine = AVAudioEngine()
    private let mixer: VoiceMixer
    private var source: AVAudioSourceNode!
    private let lock = NSLock()
    private var bank = ClipBank(presses: [], releases: [])
    private var cache: [String: ClipBank] = [:]
    private var pressPicker = SamplePicker()
    private var releasePicker = SamplePicker()
    private var configObserver: NSObjectProtocol?

    // Settings, read on the listener thread under `lock`.
    private var _enabled = true
    private var _releases = true
    private var _spatialWidth: Float = 0.6

    public var isEnabled: Bool {
        get { lock.withLock { _enabled } }
        set { lock.withLock { _enabled = newValue } }
    }

    /// Play a release sound when a key comes back up.
    public var playsReleases: Bool {
        get { lock.withLock { _releases } }
        set { lock.withLock { _releases = newValue } }
    }

    /// 0 plays every key in the centre; 1 spreads the keyboard across the full stereo field.
    public var spatialWidth: Float {
        get { lock.withLock { _spatialWidth } }
        set { lock.withLock { _spatialWidth = max(0, min(1, newValue)) } }
    }

    /// 0...1, applied at the output mixer.
    public var volume: Float = 0.6 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    /// Output latency the device reports (its buffer plus its own delay), in milliseconds.
    public var outputLatencyMs: Double {
        guard !engine.isInManualRenderingMode else { return 0 }
        let output = engine.outputNode
        let rate = output.outputFormat(forBus: 0).sampleRate
        guard rate > 0 else { return 0 }
        return (output.presentationLatency + Double(currentIOBufferFrames()) / rate) * 1000
    }

    /// Clicks sounding right now (for tests and diagnostics).
    var activeVoices: Int { mixer.activeVoices }
    /// Diagnostics: clicks the mixer has started, and its loudest output sample so far.
    public var clicksStarted: Int { mixer.clicksStarted }
    public var peakOutput: Float { mixer.peakOutput }

    /// Pass `offlineFormat` to render into memory instead of a device (used by tests to
    /// measure what would actually come out of the speakers).
    public init(voices: Int = 32, offlineFormat: AVAudioFormat? = nil) {
        mixer = VoiceMixer(capacity: voices)
        if let offlineFormat {
            // Render in the same small slices a real device uses, so timing matches.
            try? engine.enableManualRenderingMode(.offline, format: offlineFormat,
                                                  maximumFrameCount: Self.preferredIOBufferFrames)
        }
        let mixer = self.mixer
        source = AVAudioSourceNode(format: Self.mixFormat) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            mixer.render(frames: Int(frameCount), left: left, right: right)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: Self.mixFormat)

        // An output device change (AirPods connecting or disconnecting, headphones in or
        // out) stops the engine and can leave nodes wired to the old device. Rebuild.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.rebuildForNewDevice() }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine.stop()
    }

    /// Re-wires the voice source to the current output device and restarts at low latency.
    public func rebuildForNewDevice() {
        lock.lock()
        defer { lock.unlock() }
        engine.stop()
        engine.disconnectNodeOutput(source)
        engine.connect(source, to: engine.mainMixerNode, format: Self.mixFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        if !bank.presses.isEmpty { try? start() }
    }

    /// Loads (or reuses) the profile's clips and makes them current. If anything fails,
    /// the previous profile keeps playing.
    public func load(_ profile: SoundProfile) throws {
        guard !profile.presses.isEmpty else { throw SoundEngineError.emptyProfile(profile.id) }
        let key = ([profile.id] + (profile.presses + profile.releases).map(\.path)).joined(separator: "\n")
        let loaded = try lock.withLock({ cache[key] }) ?? ClipBank(
            presses: profile.presses.map { try Self.clip(from: $0) },
            releases: profile.releases.map { try Self.clip(from: $0) }
        )
        lock.lock()
        defer { lock.unlock() }
        cache[key] = loaded
        bank = loaded
        engine.mainMixerNode.outputVolume = volume
        try start()
    }

    /// Plays the sound for one key event. Called on the key listener's thread.
    public func handle(_ event: KeyEvent) {
        lock.lock()
        let clip: Clip
        let pan: Float
        switch event {
        case .down(let p):
            guard _enabled, let i = pressPicker.pick(from: bank.presses.count) else { return lock.unlock() }
            clip = bank.presses[i]
            pan = p * _spatialWidth
        case .up(let p):
            guard _enabled, _releases, let i = releasePicker.pick(from: bank.releases.count) else { return lock.unlock() }
            clip = bank.releases[i]
            pan = p * _spatialWidth
        }
        let running = engine.isRunning
        lock.unlock()

        let gains = Self.gains(pan: pan, level: Float.random(in: 0.88...1.0))
        mixer.trigger(clip, gainLeft: gains.left, gainRight: gains.right)
        if !running { lock.withLock { try? start() } }
    }

    /// Plays a centred press, e.g. to preview a profile or volume change.
    public func preview() {
        handle(.down(pan: 0))
    }

    /// Equal-power stereo gains for a position from -1 (left) to 1 (right): loudness stays
    /// the same wherever the key is.
    static func gains(pan: Float, level: Float) -> (left: Float, right: Float) {
        let angle = (max(-1, min(1, pan)) + 1) * .pi / 4
        return (cos(angle) * level, sin(angle) * level)
    }

    /// Offline mode only: renders `frames` of output and returns one sample array per channel.
    public func renderOffline(frames: Int) throws -> [[Float]] {
        guard engine.isInManualRenderingMode else { return [] }
        let format = engine.manualRenderingFormat
        let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        var out = Array(repeating: [Float](), count: Int(format.channelCount))
        while out[0].count < frames {
            let want = AVAudioFrameCount(min(Int(chunk.frameCapacity), frames - out[0].count))
            let status = try engine.renderOffline(want, to: chunk)
            guard status == .success else { break }
            for c in 0..<out.count {
                out[c] += UnsafeBufferPointer(start: chunk.floatChannelData![c], count: Int(chunk.frameLength))
            }
        }
        return out
    }

    // Must be called with `lock` held.
    private func start() throws {
        guard !engine.isRunning else { return }
        requestSmallIOBuffer()
        engine.prepare()
        try engine.start()
        // Some devices only accept the buffer size once the unit is running.
        if currentIOBufferFrames() > Self.preferredIOBufferFrames { requestSmallIOBuffer() }
    }

    private func requestSmallIOBuffer() {
        guard !engine.isInManualRenderingMode, let unit = engine.outputNode.audioUnit else { return }
        var frames = Self.preferredIOBufferFrames
        AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                             &frames, UInt32(MemoryLayout<UInt32>.size))
    }

    private func currentIOBufferFrames() -> UInt32 {
        guard !engine.isInManualRenderingMode, let unit = engine.outputNode.audioUnit else { return 0 }
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, &size)
        return frames
    }

    private static func clip(from url: URL) throws -> Clip {
        let converted = try convert(decode(url))
        return Clip(UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength)))
    }

    /// Converts a clip to `internalFormat` (sample rate and channel count) at maximum quality.
    static func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let target = internalFormat
        if buffer.format == target { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: target) else {
            throw SoundEngineError.unsupportedFormat
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
        converter.downmix = true
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw SoundEngineError.unsupportedFormat
        }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return out
    }

    private static func decode(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw SoundEngineError.unreadable(url)
        }
        try file.read(into: buffer)
        return buffer
    }
}

public enum SoundEngineError: LocalizedError {
    case emptyProfile(String)
    case unsupportedFormat
    case unreadable(URL)

    public var errorDescription: String? {
        switch self {
        case .emptyProfile(let id): "Profile \(id) has no samples."
        case .unsupportedFormat: "A sound file uses an unsupported audio format."
        case .unreadable(let url): "Could not read \(url.lastPathComponent)."
        }
    }
}
