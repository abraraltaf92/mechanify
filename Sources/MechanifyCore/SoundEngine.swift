import AudioToolbox
import AVFoundation

/// Low-latency click playback.
///
/// - Every press and release sample of the active profile is decoded into memory up
///   front, at the recording's own sample rate (no resampling on load).
/// - A fixed pool of always-running player nodes is fed in rotation, so a keystroke
///   costs one `scheduleBuffer` call and fast typing overlaps instead of cutting off.
/// - Each voice is panned to where the key sits on the keyboard.
/// - The output device is asked for a small I/O buffer to keep latency down.
///
/// `handle(_:)` is safe to call from the key listener's thread; settings and `load`
/// can be called from the main thread.
public final class SoundEngine {
    public static let defaultPoolSize = 16
    /// Requested output buffer. 128 frames is ~3 ms at 44.1 kHz; the device may round it.
    public static let preferredIOBufferFrames: UInt32 = 128

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var players: [AVAudioPlayerNode] = []
    private var format: AVAudioFormat?
    private var rotation: RoundRobin
    private var pressBuffers: [AVAudioPCMBuffer] = []
    private var releaseBuffers: [AVAudioPCMBuffer] = []
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
        let output = engine.outputNode
        let rate = output.outputFormat(forBus: 0).sampleRate
        guard rate > 0 else { return 0 }
        return (output.presentationLatency + Double(currentIOBufferFrames()) / rate) * 1000
    }

    public init(poolSize: Int = SoundEngine.defaultPoolSize) {
        rotation = RoundRobin(count: poolSize)
        // An output device change (AirPods connecting or disconnecting, headphones in or
        // out) stops the engine and can leave the voices wired to the old device. Rebuild.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.rebuildForNewDevice() }
    }

    /// Re-wires every voice to the current output device and restarts at low latency.
    public func rebuildForNewDevice() {
        lock.lock()
        defer { lock.unlock() }
        guard let format else { return }
        engine.stop()
        for player in players {
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        try? start()
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine.stop()
    }

    /// Decodes the profile's samples and (re)wires the player pool for their format.
    public func load(_ profile: SoundProfile) throws {
        let presses = try profile.presses.map(Self.decode)
        let releases = try profile.releases.map(Self.decode)
        guard let first = presses.first else { throw SoundEngineError.emptyProfile(profile.id) }
        guard (presses + releases).allSatisfy({ $0.format == first.format }) else {
            throw SoundEngineError.mixedFormats(profile.id)
        }

        lock.lock()
        defer { lock.unlock() }
        if format != first.format {
            engine.stop()
            players.forEach { engine.detach($0) }
            players = (0..<rotation.count).map { _ in AVAudioPlayerNode() }
            for player in players {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: first.format)
            }
            format = first.format
        }
        pressBuffers = presses
        releaseBuffers = releases
        engine.mainMixerNode.outputVolume = volume
        try start()
    }

    /// Plays the sound for one key event. Called on the key listener's thread.
    public func handle(_ event: KeyEvent) {
        lock.lock()
        defer { lock.unlock() }
        guard _enabled, !players.isEmpty else { return }

        let buffer: AVAudioPCMBuffer
        let pan: Float
        switch event {
        case .down(let p):
            guard let i = pressPicker.pick(from: pressBuffers.count) else { return }
            buffer = pressBuffers[i]
            pan = p
        case .up(let p):
            guard _releases, let i = releasePicker.pick(from: releaseBuffers.count) else { return }
            buffer = releaseBuffers[i]
            pan = p
        }
        if !engine.isRunning { try? start() }
        let player = players[rotation.take()]
        player.pan = pan * _spatialWidth
        player.volume = Float.random(in: 0.88...1.0)  // small natural variation
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Plays a centred press, e.g. to preview a profile or volume change.
    public func preview() {
        handle(.down(pan: 0))
    }

    private func start() throws {
        if !engine.isRunning {
            requestSmallIOBuffer()
            engine.prepare()
            try engine.start()
            // Some devices only accept the buffer size once the unit is running.
            if currentIOBufferFrames() > Self.preferredIOBufferFrames { requestSmallIOBuffer() }
        }
        players.forEach { if !$0.isPlaying { $0.play() } }
    }

    private func requestSmallIOBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames = Self.preferredIOBufferFrames
        AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                             &frames, UInt32(MemoryLayout<UInt32>.size))
    }

    private func currentIOBufferFrames() -> UInt32 {
        guard let unit = engine.outputNode.audioUnit else { return 0 }
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, &size)
        return frames
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
    case mixedFormats(String)
    case unreadable(URL)

    public var errorDescription: String? {
        switch self {
        case .emptyProfile(let id): "Profile \(id) has no samples."
        case .mixedFormats(let id): "Profile \(id) mixes sample formats."
        case .unreadable(let url): "Could not read \(url.lastPathComponent)."
        }
    }
}
