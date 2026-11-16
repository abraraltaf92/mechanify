import Foundation
import Testing
@testable import MechanifyCore

// Feeds HID key reports through the listener (no hardware or permission needed) and
// checks what reaches the sound engine.

private let laptop = KeyboardInfo(id: KeyboardInfo.builtInID, name: "Built-in keyboard", isBuiltIn: true)
private let mech = KeyboardInfo(id: "1234:5678:SN1", name: "Keychron K2", isBuiltIn: false)

private func recording(_ setup: (KeyListener) -> Void = { _ in }) -> (KeyListener, () -> [KeyEvent]) {
    let listener = KeyListener()
    let box = Box()
    listener.onKey = { box.events.append($0) }
    setup(listener)
    return (listener, { box.events })
}

private final class Box: @unchecked Sendable { var events: [KeyEvent] = []; var keyboards: [KeyboardInfo] = [] }

@Test func pressAndReleaseBecomeDownAndUp() {
    let (listener, seen) = recording()
    listener.process(page: 0x07, usage: 0x04, pressed: true, keyboard: laptop)   // A
    listener.process(page: 0x07, usage: 0x04, pressed: false, keyboard: laptop)
    #expect(seen().count == 2)
    guard case .down(let p1) = seen()[0], case .up(let p2) = seen()[1] else {
        Issue.record("expected down then up, got \(seen())")
        return
    }
    #expect(p1 < -0.5 && p1 == p2, "A is on the left, same position for press and release")
}

@Test func repeatedReportsOnlyCountRealEdges() {
    let (listener, seen) = recording()
    listener.process(page: 0x07, usage: 0x2C, pressed: false, keyboard: laptop)  // release with no press
    listener.process(page: 0x07, usage: 0x2C, pressed: true, keyboard: laptop)
    listener.process(page: 0x07, usage: 0x2C, pressed: true, keyboard: laptop)   // duplicate report
    listener.process(page: 0x07, usage: 0x2C, pressed: false, keyboard: laptop)
    listener.process(page: 0x07, usage: 0x2C, pressed: false, keyboard: laptop)  // duplicate
    #expect(seen().count == 2, "one press, one release")
}

@Test func silencedKeyboardMakesNoSoundOthersStillDo() {
    let (listener, seen) = recording { $0.silencedKeyboards = [mech.id] }
    listener.process(page: 0x07, usage: 0x04, pressed: true, keyboard: mech)
    listener.process(page: 0x07, usage: 0x04, pressed: false, keyboard: mech)
    #expect(seen().isEmpty, "the mechanical keyboard stays quiet")
    listener.process(page: 0x07, usage: 0x04, pressed: true, keyboard: laptop)
    #expect(seen().count == 1, "the laptop keyboard still clicks, even with the same key")
    listener.silencedKeyboards = []
    listener.process(page: 0x07, usage: 0x05, pressed: true, keyboard: mech)
    #expect(seen().count == 2, "turning it back on works immediately")
}

@Test func sameKeyHeldOnTwoKeyboardsIsTrackedPerKeyboard() {
    let (listener, seen) = recording()
    listener.process(page: 0x07, usage: 0x04, pressed: true, keyboard: laptop)
    listener.process(page: 0x07, usage: 0x04, pressed: true, keyboard: mech)
    listener.process(page: 0x07, usage: 0x04, pressed: false, keyboard: laptop)
    listener.process(page: 0x07, usage: 0x04, pressed: false, keyboard: mech)
    #expect(seen().count == 4)
}

@Test func nonKeyReportsAreIgnored() {
    let (listener, seen) = recording()
    listener.process(page: 0x07, usage: 0x00, pressed: true, keyboard: laptop)   // reserved
    listener.process(page: 0x07, usage: 0x01, pressed: true, keyboard: laptop)   // rollover error
    listener.process(page: 0x07, usage: 0xFFFF_FFFF, pressed: true, keyboard: laptop)
    listener.process(page: 0x0C, usage: 0xE9, pressed: true, keyboard: laptop)   // consumer: volume up
    listener.process(page: 0xFF, usage: 0x04, pressed: true, keyboard: laptop)   // other vendor usage
    #expect(seen().isEmpty)
}

@Test func eachKeyboardIsAnnouncedOnceWhenItFirstTypes() async {
    let listener = KeyListener()
    let box = Box()
    listener.onKeyboardTyped = { box.keyboards.append($0) }
    listener.process(page: 0x07, usage: 0x04, pressed: true, keyboard: mech)
    listener.process(page: 0x07, usage: 0x04, pressed: false, keyboard: mech)
    listener.process(page: 0x07, usage: 0x05, pressed: true, keyboard: mech)
    listener.process(page: 0x07, usage: 0x04, pressed: true, keyboard: laptop)
    await MainActor.run {}  // announcements arrive on the main queue
    #expect(box.keyboards.map(\.id) == [mech.id, laptop.id])
}

@Test func silencedKeyboardsAreStillAnnounced() async {
    let listener = KeyListener()
    listener.silencedKeyboards = [mech.id]
    let box = Box()
    listener.onKeyboardTyped = { box.keyboards.append($0) }
    listener.process(page: 0x07, usage: 0x04, pressed: true, keyboard: mech)
    await MainActor.run {}
    #expect(box.keyboards == [mech])
}

@Test func stopWithoutStartIsSafe() {
    let listener = KeyListener()
    listener.stop()
    listener.stop()
}

// MARK: HID usage → key

@Test func hidUsagesMapToMacKeys() {
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x04) == 0)      // A
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x1D) == 6)      // Z
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x1E) == 18)     // 1
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x27) == 29)     // 0
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x28) == 36)     // Return
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x2C) == 49)     // Space
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x2A) == 51)     // Delete
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x3A) == 122)    // F1
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x52) == 126)    // Up
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x62) == 82)     // keypad 0
    #expect(HIDKeys.keyCode(page: 0xFF, usage: 0x03) == 63)     // fn / Globe
    #expect(HIDKeys.keyCode(page: 0x07, usage: 0x01) == nil)
    #expect(HIDKeys.keyCode(page: 0x09, usage: 0x04) == nil)    // buttons page
}

@Test func everyMappedKeyHasAPosition() {
    for usage in UInt32(0)...0xFF {
        guard let code = HIDKeys.keyCode(page: 0x07, usage: usage) else { continue }
        #expect(KeyLayout.column[code] != nil, "HID usage 0x\(String(usage, radix: 16)) → key \(code) has no position")
    }
    #expect(KeyLayout.column[63] != nil, "fn")
}

@Test func lettersCoverTheAlphabetWithoutDuplicates() {
    let codes = (UInt32(0x04)...0x1D).compactMap { HIDKeys.keyCode(page: 0x07, usage: $0) }
    #expect(codes.count == 26 && Set(codes).count == 26)
}

@Test func everyMappedKeyStaysInRange() {
    for code in KeyLayout.column.keys {
        #expect((-1...1).contains(KeyLayout.pan(forKeyCode: code)), "key code \(code)")
    }
    #expect(KeyLayout.pan(forKeyCode: -1) == 0)
    #expect(KeyLayout.pan(forKeyCode: .max) == 0)
}

@Test func rowsRunLeftToRight() {
    let rows: [[Int64]] = [
        [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 51],
        [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
        [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 36],
        [10, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44],
    ]
    for row in rows {
        let pans = row.map { KeyLayout.pan(forKeyCode: $0) }
        #expect(pans == pans.sorted(), "row \(row) is ordered left to right")
    }
}

// MARK: Keyboard identity and choices

@Test func keyboardsAreIdentifiedStably() {
    let a = KeyboardInfo.identify(product: "Keychron K2", vendorID: 1452, productID: 591, serial: "ABC", builtIn: false)
    let again = KeyboardInfo.identify(product: "Keychron K2", vendorID: 1452, productID: 591, serial: "ABC", builtIn: false)
    let other = KeyboardInfo.identify(product: "Keychron K2", vendorID: 1452, productID: 591, serial: "XYZ", builtIn: false)
    #expect(a.id == again.id, "the same keyboard reconnecting keeps its identity")
    #expect(a.id != other.id, "two keyboards of the same model are told apart by serial")
    #expect(a.name == "Keychron K2" && !a.isBuiltIn)

    let laptopParts = [
        KeyboardInfo.identify(product: "Apple Internal Keyboard / Trackpad", vendorID: 0, productID: 0, serial: nil, builtIn: true),
        KeyboardInfo.identify(product: "Apple Internal Keyboard / Trackpad", vendorID: 0, productID: 857, serial: "FM7", builtIn: true),
    ]
    #expect(Set(laptopParts.map(\.id)) == [KeyboardInfo.builtInID], "all built-in parts are one keyboard")

    let noSerial = KeyboardInfo.identify(product: "  ", vendorID: 1, productID: 2, serial: "", builtIn: false)
    #expect(noSerial.name == "Keyboard" && noSerial.id == "1:2:Keyboard")
}

@Test func keyboardChoicesAreRememberedAndCanBeUndone() throws {
    var prefs = KeyboardPreferences()
    #expect(prefs.remember(mech) == true, "first time: ask")
    #expect(prefs.remember(mech) == false, "second time: don't ask again")
    #expect(prefs.remember(laptop) == false, "never ask about the built-in keyboard")
    #expect(prefs.isKnown(mech.id) && prefs.isKnown(KeyboardInfo.builtInID))

    prefs.setSounds(false, for: mech.id)
    #expect(prefs.isSilenced(mech.id) && !prefs.isSilenced(laptop.id))

    let restored = try JSONDecoder().decode(KeyboardPreferences.self, from: JSONEncoder().encode(prefs))
    #expect(restored == prefs, "survives a restart")

    prefs.setSounds(true, for: mech.id)
    #expect(!prefs.isSilenced(mech.id))
    prefs.setSounds(false, for: mech.id)
    prefs.forget(mech.id)
    #expect(!prefs.isKnown(mech.id) && !prefs.isSilenced(mech.id), "forgetting clears the choice")
    #expect(prefs.remember(mech) == true, "and it's asked about again")
}

@Test func renamedKeyboardKeepsItsChoice() {
    var prefs = KeyboardPreferences()
    prefs.remember(mech)
    prefs.setSounds(false, for: mech.id)
    prefs.remember(KeyboardInfo(id: mech.id, name: "My Keychron", isBuiltIn: false))
    #expect(prefs.known.first?.name == "My Keychron")
    #expect(prefs.isSilenced(mech.id))
}
