import Foundation
import Testing
@testable import MechanifyCore

/// Deterministic generator for repeatable tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func pickerNeverRepeatsBackToBack() {
    var picker = SamplePicker(generator: SeededGenerator(state: 42))
    var previous: Int?
    var seen = Set<Int>()
    for _ in 0..<2_000 {
        let i = picker.pick(from: 5)!
        #expect((0..<5).contains(i))
        #expect(i != previous)
        previous = i
        seen.insert(i)
    }
    #expect(seen.count == 5)  // every sample still gets used
}

@Test func pickerHandlesTinyCounts() {
    var picker = SamplePicker(generator: SeededGenerator(state: 1))
    #expect(picker.pick(from: 0) == nil)
    #expect(picker.pick(from: 1) == 0)
    #expect(picker.pick(from: 1) == 0)
}

@Test func discoverFindsProfilesInPreferredOrder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let layout: [(String, [String])] = [
        ("Classic", ["b.wav", "a.wav"]),                                    // flat folder: presses only
        ("Cherry MX Red", ["down/p1.wav", "down/p2.wav", "up/r1.wav"]),     // down/ + up/
        ("custom", ["down/k.WAV"]),
        ("empty", ["notes.txt", "up/r.wav"]),                               // releases alone don't count
    ]
    for (folder, files) in layout {
        for f in files {
            let url = root.appendingPathComponent(folder).appendingPathComponent(f)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
    }

    let profiles = SoundProfile.discover(in: root)
    #expect(profiles.map(\.id) == ["Cherry MX Red", "Classic", "custom"])
    #expect(profiles[0].presses.map(\.lastPathComponent) == ["p1.wav", "p2.wav"])
    #expect(profiles[0].releases.map(\.lastPathComponent) == ["r1.wav"])
    #expect(profiles[1].presses.map(\.lastPathComponent) == ["a.wav", "b.wav"])
    #expect(profiles[1].releases.isEmpty)
}

@Test func keyPositionsSpreadLeftToRight() {
    let a = KeyLayout.pan(forKeyCode: 0)      // A
    let g = KeyLayout.pan(forKeyCode: 5)      // G
    let l = KeyLayout.pan(forKeyCode: 37)     // L
    let ret = KeyLayout.pan(forKeyCode: 36)   // Return
    #expect(a < g && g < l && l < ret)
    #expect(a < -0.5 && ret > 0.8)
    #expect(abs(KeyLayout.pan(forKeyCode: 49)) < 0.01)    // Space sits in the middle
    #expect(KeyLayout.pan(forKeyCode: 9999) == 0)         // unknown keys too
    for code: Int64 in [53, 50, 51, 48, 57, 6, 124] {
        #expect((-1...1).contains(KeyLayout.pan(forKeyCode: code)))
    }
}

@Test func bundledProfilesDecodeAndPlay() throws {
    // Uses the real generated profiles in Resources/Profiles.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Profiles")
    let profiles = SoundProfile.discover(in: root)
    #expect(profiles.map(\.id) == SoundProfile.preferredOrder)
    let engine = SoundEngine()
    engine.volume = 0
    for profile in profiles {
        #expect(profile.presses.count >= 9)
        #expect(profile.releases.count >= 9)
        try engine.load(profile)
        engine.handle(.down(pan: -0.8))
        engine.handle(.up(pan: 0.8))
    }
    #expect(engine.outputLatencyMs >= 0)
}
