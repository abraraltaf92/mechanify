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

@Test func roundRobinCyclesThroughEverySlot() {
    var rr = RoundRobin(count: 4)
    #expect((0..<9).map { _ in rr.take() } == [0, 1, 2, 3, 0, 1, 2, 3, 0])
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

@Test func discoverFindsWavFoldersInPreferredOrder() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for (folder, files) in [("Classic", ["b.wav", "a.wav"]), ("Cherry MX Red", ["x.wav"]), ("custom", ["k.WAV"]), ("empty", ["notes.txt"])] {
        let dir = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in files { FileManager.default.createFile(atPath: dir.appendingPathComponent(f).path, contents: Data()) }
    }

    let profiles = SoundProfile.discover(in: root)
    #expect(profiles.map(\.id) == ["Cherry MX Red", "Classic", "custom"])
    #expect(profiles[1].samples.map(\.lastPathComponent) == ["a.wav", "b.wav"])
    #expect(profiles[0].displayName == "Cherry MX Red")
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
        #expect(profile.samples.count >= 9)
        try engine.load(profile)
        engine.playClick()
    }
}
