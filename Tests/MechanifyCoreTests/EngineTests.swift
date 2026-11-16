import AVFoundation
import Foundation
import Testing
@testable import MechanifyCore

// These tests render the engine's output into memory (no speakers) and measure the
// samples, so they check what the user would actually hear.

private let profilesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Profiles")
private let outputRate = 48_000.0
private let allProfiles = SoundProfile.discover(in: profilesRoot)

private func profile(_ id: String) -> SoundProfile { allProfiles.first { $0.id == id }! }

private func offlineEngine(_ profile: SoundProfile = profile("Cherry MX Clear"), volume: Float = 1) throws -> SoundEngine {
    let engine = SoundEngine(offlineFormat: AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 2)!)
    engine.volume = volume
    try engine.load(profile)
    return engine
}

private func frames(ms: Double) -> Int { Int(outputRate * ms / 1000) }
private func peak(_ x: [Float]) -> Float { x.map(abs).max() ?? 0 }
private func energy(_ x: [Float]) -> Float { x.reduce(0) { $0 + $1 * $1 } }

// MARK: Sound comes out

@Test func silentUntilAKeyIsPressed() throws {
    let engine = try offlineEngine()
    let out = try engine.renderOffline(frames: frames(ms: 200))
    #expect(peak(out[0]) == 0 && peak(out[1]) == 0)
}

@Test(arguments: SoundProfile.preferredOrder)
func everyProfilePlaysPressAndRelease(_ id: String) throws {
    let engine = try offlineEngine(profile(id))
    engine.handle(.down(pan: 0))
    let press = try engine.renderOffline(frames: frames(ms: 250))
    engine.handle(.up(pan: 0))
    let release = try engine.renderOffline(frames: frames(ms: 250))
    #expect(peak(press[0]) > 0.05, "press is audible")
    #expect(peak(release[0]) > 0.001, "release is audible")
    #expect(peak(release[0]) < peak(press[0]), "release is quieter than press")
    #expect(peak(press[0]) <= 1.0, "no clipping")
}

/// Milliseconds until a signal first reaches `fraction` of its peak.
private func msUntil(_ fraction: Float, of x: [Float], rate: Double = outputRate) -> Double? {
    let p = peak(x)
    guard p > 0, let i = x.firstIndex(where: { abs($0) >= p * fraction }) else { return nil }
    return Double(i) / rate * 1000
}

@Test(arguments: SoundProfile.preferredOrder)
func clickIsHeardPromptly(_ id: String) throws {
    // Engine: a click starts on the very next 128-frame slice (< 2.7 ms).
    // End to end: the click itself (30% of its peak) within 15 ms of the key event.
    let engine = try offlineEngine(profile(id))
    for _ in 0..<8 {
        engine.handle(.down(pan: 0))
        let out = try engine.renderOffline(frames: frames(ms: 200))[0]
        let first = try #require(msUntil(0.001, of: out), "\(id) made a sound")
        let click = try #require(msUntil(0.3, of: out))
        #expect(first < 3, "\(id): engine started the sound after \(first) ms")
        #expect(click < 15, "\(id): click heard after \(click) ms")
    }
}

@Test(arguments: SoundProfile.preferredOrder)
func everyBundledClipStartsOnItsClick(_ id: String) throws {
    for url in profile(id).presses + profile(id).releases {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let ms = try #require(msUntil(0.3, of: samples, rate: file.processingFormat.sampleRate))
        #expect(ms < 10, "\(url.lastPathComponent) in \(id) reaches its click after \(ms) ms")
        #expect(peak(samples) < 0.95, "\(url.lastPathComponent) in \(id) is not clipped")
        #expect(buffer.frameLength > 0)
    }
}

@Test func switchingBetween44And96kHzProfilesKeepsPlaying() throws {
    let engine = try offlineEngine(profile("Classic"))  // 44.1 kHz
    for id in ["Cherry MX Red", "Cherry MX Clear", "Cherry MX Red", "Gateron Black"] {  // 96k, 44.1k, ...
        try engine.load(profile(id))
        engine.handle(.down(pan: 0))
        #expect(peak(try engine.renderOffline(frames: frames(ms: 200))[0]) > 0.05, "\(id) plays after switch")
    }
}

// MARK: Settings

@Test func disabledIsSilent() throws {
    let engine = try offlineEngine()
    engine.isEnabled = false
    engine.handle(.down(pan: 0))
    engine.handle(.up(pan: 0))
    #expect(peak(try engine.renderOffline(frames: frames(ms: 250))[0]) == 0)
    engine.isEnabled = true
    engine.handle(.down(pan: 0))
    #expect(peak(try engine.renderOffline(frames: frames(ms: 250))[0]) > 0.05, "re-enabling works")
}

@Test func releasesOffSilencesKeyUpOnly() throws {
    let engine = try offlineEngine()
    engine.playsReleases = false
    engine.handle(.up(pan: 0))
    #expect(peak(try engine.renderOffline(frames: frames(ms: 200))[0]) == 0)
    engine.handle(.down(pan: 0))
    #expect(peak(try engine.renderOffline(frames: frames(ms: 200))[0]) > 0.05)
}

@Test func profileWithoutReleasesIgnoresKeyUp() throws {
    let clear = profile("Cherry MX Clear")
    let engine = try offlineEngine(SoundProfile(id: "press only", presses: clear.presses))
    engine.handle(.up(pan: 0))
    #expect(peak(try engine.renderOffline(frames: frames(ms: 200))[0]) == 0)
}

@Test func volumeScalesOutput() throws {
    let one = SoundProfile(id: "one", presses: [profile("Cherry MX Red").presses[0]])  // same clip every time
    let loud = try offlineEngine(one, volume: 1)
    let quiet = try offlineEngine(one, volume: 0.25)
    let muted = try offlineEngine(one, volume: 0)
    for e in [loud, quiet, muted] { e.handle(.down(pan: 0)) }
    let l = peak(try loud.renderOffline(frames: frames(ms: 200))[0])
    let q = peak(try quiet.renderOffline(frames: frames(ms: 200))[0])
    let m = peak(try muted.renderOffline(frames: frames(ms: 200))[0])
    #expect(m == 0)
    #expect(q > l * 0.2 && q < l * 0.3, "quarter volume is a quarter as loud (±12% gain jitter)")
}

// MARK: Spatial audio

@Test func leftKeysSoundLeftAndRightKeysSoundRight() throws {
    let engine = try offlineEngine()
    engine.spatialWidth = 1
    engine.handle(.down(pan: -1))
    let left = try engine.renderOffline(frames: frames(ms: 250))
    engine.handle(.down(pan: 1))
    let right = try engine.renderOffline(frames: frames(ms: 250))
    #expect(energy(left[1]) < energy(left[0]) * 0.001, "pan -1 is entirely in the left channel")
    #expect(energy(right[0]) < energy(right[1]) * 0.001, "pan +1 is entirely in the right channel, from the first sample")
}

@Test func everyPositionKeepsTheSameLoudness() {
    // Equal-power placement: left² + right² is the same wherever the key is.
    for pan: Float in stride(from: -1, through: 1, by: 0.25) {
        let g = SoundEngine.gains(pan: pan, level: 1)
        #expect(abs(g.left * g.left + g.right * g.right - 1) < 0.0001)
    }
    #expect(SoundEngine.gains(pan: -1, level: 1).right < 0.0001)
    #expect(SoundEngine.gains(pan: 1, level: 1).left < 0.0001)
    #expect(SoundEngine.gains(pan: -7, level: 1) == SoundEngine.gains(pan: -1, level: 1), "clamped")
}

@Test func widthZeroPlaysCentred() throws {
    let engine = try offlineEngine()
    engine.spatialWidth = 0
    engine.handle(.down(pan: -1))
    let out = try engine.renderOffline(frames: frames(ms: 250))
    let ratio = energy(out[0]) / energy(out[1])
    #expect(abs(ratio - 1) < 0.001)
}

@Test func widthIsClamped() throws {
    let engine = try offlineEngine()
    engine.spatialWidth = 5
    #expect(engine.spatialWidth == 1)
    engine.spatialWidth = -2
    #expect(engine.spatialWidth == 0)
}

// MARK: Fast typing and odd sequences

@Test func typingFasterThanTheVoicesDoesNotBreak() throws {
    let engine = try offlineEngine()
    for i in 0..<200 {  // 200 events at once: far more than the 32 voices
        engine.handle(i.isMultiple(of: 2) ? .down(pan: Float(i % 7) / 3 - 1) : .up(pan: 0))
    }
    let out = try engine.renderOffline(frames: frames(ms: 300))
    #expect(out[0].allSatisfy { $0.isFinite })
    #expect(peak(out[0]) > 0.05)
    engine.handle(.down(pan: 0))
    #expect(peak(try engine.renderOffline(frames: frames(ms: 200))[0]) > 0.05, "still plays afterwards")
}

@Test func releaseWithoutPressAndDoublePressAreFine() throws {
    let engine = try offlineEngine()
    engine.handle(.up(pan: 0.3))          // key was already down when the app started
    engine.handle(.down(pan: 0))
    engine.handle(.down(pan: 0))          // two keys at once
    #expect(peak(try engine.renderOffline(frames: frames(ms: 250))[0]) > 0.05)
}

@Test func outputDeviceChangeKeepsPlaying() throws {
    let engine = try offlineEngine()
    for _ in 0..<3 { engine.rebuildForNewDevice() }
    engine.handle(.down(pan: 0))
    #expect(peak(try engine.renderOffline(frames: frames(ms: 200))[0]) > 0.05)
}

@Test func eventsBeforeAnyProfileLoadAreIgnored() throws {
    let engine = SoundEngine(offlineFormat: AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 2)!)
    engine.handle(.down(pan: 0))
    engine.handle(.up(pan: 0))
    engine.rebuildForNewDevice()
}

// MARK: Bad profiles

@Test func emptyProfileIsRejected() {
    let engine = SoundEngine(offlineFormat: AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 2)!)
    #expect(throws: SoundEngineError.self) { try engine.load(SoundProfile(id: "empty", presses: [])) }
}

@Test func mixedSampleRatesInOneProfileStillPlay() throws {
    // 44.1 kHz and 96 kHz clips side by side: both are converted to the internal format.
    let mixed = SoundProfile(id: "mixed", presses: [profile("Classic").presses[0], profile("Cherry MX Red").presses[0]])
    let engine = try offlineEngine(mixed)
    for _ in 0..<4 {
        engine.handle(.down(pan: 0))
        #expect(peak(try engine.renderOffline(frames: frames(ms: 200))[0]) > 0.05)
    }
}

@Test func conversionKeepsLengthAndLevel() throws {
    let file = try AVAudioFile(forReading: profile("Cherry MX Red").presses[0])  // 96 kHz
    let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: source)
    let converted = try SoundEngine.convert(source)
    #expect(converted.format == SoundEngine.internalFormat)
    let seconds = (Double(source.frameLength) / source.format.sampleRate, Double(converted.frameLength) / 48_000)
    #expect(abs(seconds.0 - seconds.1) < 0.002, "same duration")
    let peakIn = peak(Array(UnsafeBufferPointer(start: source.floatChannelData![0], count: Int(source.frameLength))))
    let peakOut = peak(Array(UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength))))
    #expect(abs(peakIn - peakOut) < 0.05, "same loudness")
}

@Test func unreadableFileIsRejectedAndOldProfileKeepsPlaying() throws {
    let bogus = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
    try Data("not audio".utf8).write(to: bogus)
    defer { try? FileManager.default.removeItem(at: bogus) }
    let engine = try offlineEngine()
    #expect(throws: (any Error).self) { try engine.load(SoundProfile(id: "bad", presses: [bogus])) }
    engine.handle(.down(pan: 0))
    #expect(peak(try engine.renderOffline(frames: frames(ms: 200))[0]) > 0.05)
}

@Test func missingProfilesFolderGivesNoProfiles() {
    #expect(SoundProfile.discover(in: URL(fileURLWithPath: "/nonexistent/\(UUID())")).isEmpty)
}

// MARK: Threads

@Test(.timeLimit(.minutes(1)))
func keyThreadsAndSettingsChangesRaceSafely() async throws {
    // Real-time engine (muted): key events arrive on several threads while the main
    // thread switches profiles and settings, as happens when typing during a change.
    let engine = SoundEngine()
    engine.volume = 0
    try engine.load(profile("Classic"))
    await withTaskGroup(of: Void.self) { group in
        for t in 0..<4 {
            group.addTask {
                for i in 0..<2_000 {
                    engine.handle((i + t).isMultiple(of: 2) ? .down(pan: Float(i % 5) / 2 - 1) : .up(pan: 0))
                }
            }
        }
        group.addTask {
            for i in 0..<30 {
                try? engine.load(profile(SoundProfile.preferredOrder[i % 5]))
                engine.isEnabled = !i.isMultiple(of: 3)
                engine.playsReleases = i.isMultiple(of: 2)
                engine.spatialWidth = Float(i % 10) / 10
                if i.isMultiple(of: 7) { engine.rebuildForNewDevice() }
            }
        }
    }
    engine.isEnabled = true
    engine.handle(.down(pan: 0))
}

@Test func realDeviceLatencyIsReported() throws {
    let engine = SoundEngine()
    engine.volume = 0
    try engine.load(profile("Classic"))
    let ms = engine.outputLatencyMs
    #expect(ms > 0 && ms.isFinite)
    print("output latency on this Mac's current device: \(String(format: "%.1f", ms)) ms")
}

