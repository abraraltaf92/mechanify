import CoreGraphics
import Testing
@testable import MechanifyCore

// Feeds synthetic keyboard events through the listener's event handling (no tap or
// permission needed) and checks what reaches the sound engine.

private func record(_ events: [(CGEventType, CGEvent)]) -> [KeyEvent] {
    let listener = KeyListener()
    var seen: [KeyEvent] = []
    listener.onKey = { seen.append($0) }
    for (type, event) in events { listener.handle(type, event) }
    return seen
}

private func key(_ code: CGKeyCode, down: Bool, repeating: Bool = false) -> (CGEventType, CGEvent) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    if repeating { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    return (down ? .keyDown : .keyUp, event)
}

@Test func pressAndReleaseBecomeDownAndUp() {
    let seen = record([key(0, down: true), key(0, down: false)])  // A
    #expect(seen.count == 2)
    guard case .down(let p1) = seen[0], case .up(let p2) = seen[1] else {
        Issue.record("expected down then up, got \(seen)")
        return
    }
    #expect(p1 < -0.5 && p1 == p2, "A is on the left, same position for press and release")
}

@Test func holdingAKeyPlaysOnce() {
    let seen = record([
        key(4, down: true),
        key(4, down: true, repeating: true),
        key(4, down: true, repeating: true),
        key(4, down: false),
    ])
    #expect(seen.count == 2, "one press and one release, no auto-repeat clicks")
}

@Test func otherEventTypesAreIgnored() {
    let flags = CGEvent(source: nil)!
    let seen = record([(.flagsChanged, flags), (.mouseMoved, flags), (.leftMouseDown, flags)])
    #expect(seen.isEmpty)
}

@Test func tapTimeoutBeforeStartDoesNotCrash() {
    let seen = record([(.tapDisabledByTimeout, CGEvent(source: nil)!), (.tapDisabledByUserInput, CGEvent(source: nil)!)])
    #expect(seen.isEmpty)
}

@Test func stopWithoutStartIsSafe() {
    let listener = KeyListener()
    listener.stop()
    listener.stop()
}

@Test func everyMappedKeyStaysInRange() {
    for code in KeyLayout.column.keys {
        let pan = KeyLayout.pan(forKeyCode: code)
        #expect((-1...1).contains(pan), "key code \(code)")
    }
    #expect(KeyLayout.pan(forKeyCode: -1) == 0)
    #expect(KeyLayout.pan(forKeyCode: .max) == 0)
}

@Test func rowsRunLeftToRight() {
    let rows: [[Int64]] = [
        [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 51],  // 1 … = Delete
        [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],  // Q … ] \
        [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 36],             // A … ' Return
        [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],                   // Z … /
    ]
    for row in rows {
        let pans = row.map { KeyLayout.pan(forKeyCode: $0) }
        #expect(pans == pans.sorted(), "row \(row) is ordered left to right")
    }
}
