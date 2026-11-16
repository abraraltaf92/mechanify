import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import MechanifyCore

// Tests for the 1.2 features: modifier keys, numpad positions, auto-mute, stats, tone,
// and choosing the output device.

private let profilesRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Profiles")
private let clear = SoundProfile.discover(in: profilesRoot).first { $0.id == "Cherry MX Clear" }!

// MARK: Modifier keys

@Test func modifierEdgesComeFromTheirOwnFlagBit() {
    // Left shift goes down, then up.
    #expect(KeyLayout.modifierIsDown(keyCode: 56, flags: 0x20102) == true)
    #expect(KeyLayout.modifierIsDown(keyCode: 56, flags: 0x100) == false)
    // Both shifts held, left released: only the right-shift bit remains, so left is up.
    #expect(KeyLayout.modifierIsDown(keyCode: 56, flags: 0x20104) == false)
    #expect(KeyLayout.modifierIsDown(keyCode: 60, flags: 0x20104) == true)
    // Each modifier uses its own bit.
    for (code, bit) in KeyLayout.modifierFlag {
        #expect(KeyLayout.modifierIsDown(keyCode: code, flags: bit) == true, "key \(code) down")
        #expect(KeyLayout.modifierIsDown(keyCode: code, flags: 0) == false, "key \(code) up")
    }
    #expect(KeyLayout.modifierIsDown(keyCode: 57, flags: 0) == true, "caps lock: one press event, both ways")
    #expect(KeyLayout.modifierIsDown(keyCode: 0, flags: 0x02) == nil, "A is not a modifier")
}

private func flagsEvent(_ code: CGKeyCode, flags: UInt64) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
    event.flags = CGEventFlags(rawValue: flags)
    return event
}

@Test func listenerTurnsModifierChangesIntoDownAndUp() {
    let listener = KeyListener()
    var seen: [KeyEvent] = []
    listener.onKey = { seen.append($0) }
    listener.handle(.flagsChanged, flagsEvent(55, flags: 0x100108))  // left command down
    listener.handle(.flagsChanged, flagsEvent(55, flags: 0x100))     // left command up
    listener.handle(.flagsChanged, flagsEvent(54, flags: 0x100110))  // right command down
    #expect(seen.count == 3)
    if case .down(let left) = seen[0], case .up = seen[1], case .down(let right) = seen[2] {
        #expect(left < 0 && right > 0, "left command sounds left, right command sounds right")
    } else {
        Issue.record("unexpected events \(seen)")
    }
}

@Test func modifiersCanBeTurnedOff() {
    let listener = KeyListener()
    listener.includesModifiers = false
    var seen: [KeyEvent] = []
    listener.onKey = { seen.append($0) }
    listener.handle(.flagsChanged, flagsEvent(56, flags: 0x20102))
    listener.handle(.keyDown, CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!)
    #expect(seen.count == 1, "ordinary keys still click")
}

@Test func unknownFlagChangesAreIgnored() {
    let listener = KeyListener()
    var seen: [KeyEvent] = []
    listener.onKey = { seen.append($0) }
    listener.handle(.flagsChanged, flagsEvent(0, flags: 0x20000))
    #expect(seen.isEmpty)
}

// MARK: Key positions

@Test func numpadAndNavigationKeysSoundFarRight() {
    for code: Int64 in [82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 65, 67, 69, 71, 75, 76, 78, 81, 114, 115, 116, 117, 119, 121] {
        #expect(KeyLayout.pan(forKeyCode: code) >= 0.99, "key code \(code)")
    }
}

@Test func modifierKeysSitWhereTheyAre() {
    #expect(KeyLayout.pan(forKeyCode: 56) < -0.7)     // left shift
    #expect(KeyLayout.pan(forKeyCode: 59) < -0.7)     // left control
    #expect(KeyLayout.pan(forKeyCode: 55) < -0.4)     // left command
    #expect(KeyLayout.pan(forKeyCode: 54) > 0.4)      // right command
    #expect(KeyLayout.pan(forKeyCode: 60) > 0.7)      // right shift
}

// MARK: Auto-mute

@Test func autoMuteRules() {
    let apps: Set = ["us.zoom.xos", "com.apple.Notes"]
    #expect(AutoMute.reason(microphoneInUse: false, muteDuringCalls: true, frontmostApp: "com.apple.Safari", mutedApps: apps) == nil)
    #expect(AutoMute.reason(microphoneInUse: true, muteDuringCalls: true, frontmostApp: "com.apple.Safari", mutedApps: apps) == .microphone)
    #expect(AutoMute.reason(microphoneInUse: true, muteDuringCalls: false, frontmostApp: "com.apple.Safari", mutedApps: apps) == nil,
            "mic rule can be switched off")
    #expect(AutoMute.reason(microphoneInUse: false, muteDuringCalls: true, frontmostApp: "com.apple.Notes", mutedApps: apps) == .app("com.apple.Notes"))
    #expect(AutoMute.reason(microphoneInUse: true, muteDuringCalls: true, frontmostApp: "us.zoom.xos", mutedApps: apps) == .microphone,
            "a call wins over the app list")
    #expect(AutoMute.reason(microphoneInUse: false, muteDuringCalls: true, frontmostApp: nil, mutedApps: apps) == nil)
    #expect(AutoMute.reason(microphoneInUse: false, muteDuringCalls: true, frontmostApp: "com.apple.Notes", mutedApps: []) == nil)
}

// MARK: Stats

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Test func statsCountTodayAndRollOverAtMidnight() {
    var stats = KeyStats()
    for _ in 0..<3 { stats.recordPress(at: date("2026-11-16T23:59:00Z"), calendar: utc) }
    #expect(stats.today == 3 && stats.total == 3)
    stats.recordPress(at: date("2026-11-17T00:00:01Z"), calendar: utc)
    #expect(stats.today == 1, "a new day starts from zero")
    #expect(stats.total == 4, "the all-time count keeps going")
    #expect(stats.today(asOf: date("2026-11-18T09:00:00Z"), calendar: utc) == 0, "nothing typed yet on a later day")
    #expect(stats.today(asOf: date("2026-11-17T12:00:00Z"), calendar: utc) == 1)
}

@Test func statsSurviveSavingAndReset() throws {
    var stats = KeyStats()
    stats.recordPress(at: date("2026-11-16T10:00:00Z"), calendar: utc)
    let restored = try JSONDecoder().decode(KeyStats.self, from: JSONEncoder().encode(stats))
    #expect(restored == stats)
    stats.reset()
    #expect(stats.today == 0 && stats.total == 0)
}

// MARK: Tone

/// Share of the signal's energy that is high-frequency (first differences emphasise treble).
private func brightness(_ x: [Float]) -> Float {
    var total: Float = 0, high: Float = 0
    for i in 1..<x.count {
        total += x[i] * x[i]
        let d = x[i] - x[i - 1]
        high += d * d
    }
    return high / max(total, 1e-9)
}

private func renderTone(_ tone: Float) throws -> [Float] {
    let engine = SoundEngine(offlineFormat: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
    engine.volume = 1
    engine.tone = tone
    try engine.load(SoundProfile(id: "one", presses: [clear.presses[0]]))
    engine.handle(.down(pan: 0))
    return try engine.renderOffline(frames: 9_600)[0]
}

@Test func brighterToneHasMoreTrebleAndDeeperHasLess() throws {
    let deeper = brightness(try renderTone(-1))
    let neutral = brightness(try renderTone(0))
    let brighter = brightness(try renderTone(1))
    #expect(deeper < neutral && neutral < brighter, "deeper \(deeper), neutral \(neutral), brighter \(brighter)")
    #expect(brighter > neutral * 1.3, "the change is clearly audible")
}

@Test func toneIsClampedAndNeutralLeavesSoundAlone() throws {
    let engine = SoundEngine(offlineFormat: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
    engine.tone = 3
    #expect(engine.tone == 1)
    engine.tone = -3
    #expect(engine.tone == -1)
    let out = try renderTone(0)
    #expect(out.map(abs).max()! > 0.05 && out.allSatisfy(\.isFinite))
}

// MARK: Output devices (real hardware on this Mac)

@Test func thisMacListsItsOutputs() throws {
    let outputs = AudioDevices.outputs()
    #expect(!outputs.isEmpty)
    #expect(Set(outputs.map(\.id)).count == outputs.count, "IDs are unique")
    #expect(outputs.allSatisfy { !$0.name.isEmpty })
    let current = try #require(AudioDevices.defaultOutput())
    #expect(outputs.contains(current))
    _ = AudioDevices.isMicrophoneInUse()  // must answer without opening the microphone
}

@Test func clicksFollowTheChosenOutputAndFallBackWhenItIsGone() throws {
    let engine = SoundEngine()
    engine.volume = 0
    try engine.load(clear)
    let target = try #require(AudioDevices.outputs().first)
    engine.outputDeviceUID = target.id
    #expect(engine.currentOutputName == target.name)

    engine.outputDeviceUID = "no-such-device-\(UUID())"
    #expect(engine.currentOutputName == AudioDevices.defaultOutput()?.name, "unknown device: system default")
    engine.handle(.down(pan: 0))
    #expect(engine.outputLatencyMs > 0)

    engine.outputDeviceUID = nil
    #expect(engine.currentOutputName == AudioDevices.defaultOutput()?.name)
}

@Test func countsShortenWithUnits() {
    let cases: [(Int, String)] = [
        (0, "0"), (7, "7"), (999, "999"),
        (1_000, "1K"), (1_234, "1.2K"), (1_999, "1.9K"), (12_345, "12.3K"), (99_999, "99.9K"),
        (100_000, "100K"), (123_456, "123K"), (999_999, "999K"),
        (1_000_000, "1M"), (1_250_000, "1.2M"), (45_600_000, "45.6M"), (999_999_999, "999M"),
        (1_000_000_000, "1B"), (2_500_000_000_000, "2.5T"), (-5, "0"),
    ]
    for (n, expected) in cases {
        #expect(KeyStats.compact(n) == expected, "\(n)")
    }
    // Never longer than 5 characters, so it can't crowd the menu.
    for n in [9_999, 99_999, 999_999, 9_999_999, 99_999_999, 999_999_999, Int.max] {
        #expect(KeyStats.compact(n).count <= 5, "\(n) → \(KeyStats.compact(n))")
    }
}
