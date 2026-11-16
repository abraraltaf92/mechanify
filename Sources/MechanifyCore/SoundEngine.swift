import AVFoundation

/// Low-latency click playback: every sample of the active profile is decoded into
/// memory up front, and a fixed pool of always-running player nodes is fed in
/// rotation, so a keystroke only costs one `scheduleBuffer` call.
public final class SoundEngine {
    public static let defaultPoolSize = 12

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    private var format: AVAudioFormat?
    private var rotation: RoundRobin
    private var picker = SamplePicker()
    private var configObserver: NSObjectProtocol?

    /// 0...1, applied at the output mixer.
    public var volume: Float = 0.6 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    public init(poolSize: Int = SoundEngine.defaultPoolSize) {
        rotation = RoundRobin(count: poolSize)
        // An output device change (headphones in/out) stops the engine; bring it back.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restart() }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine.stop()
    }

    /// Decodes the profile's samples and (re)wires the player pool for their format.
    public func load(_ profile: SoundProfile) throws {
        let decoded = try profile.samples.map(Self.decode)
        guard let first = decoded.first else { throw SoundEngineError.emptyProfile(profile.id) }
        guard decoded.allSatisfy({ $0.format == first.format }) else { throw SoundEngineError.mixedFormats(profile.id) }

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
        buffers = decoded
        engine.mainMixerNode.outputVolume = volume
        try start()
    }

    /// Plays one keystroke. Cheap enough to call straight from the event tap.
    public func playClick() {
        guard !buffers.isEmpty, let index = picker.pick(from: buffers.count) else { return }
        if !engine.isRunning { try? start() }
        let player = players[rotation.take()]
        player.volume = Float.random(in: 0.85...1.0)  // small natural variation
        player.scheduleBuffer(buffers[index], at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func start() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        players.forEach { if !$0.isPlaying { $0.play() } }
    }

    private func restart() {
        try? start()
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
