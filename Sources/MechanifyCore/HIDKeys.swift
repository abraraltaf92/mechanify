/// Translation from USB HID keyboard usages (what a keyboard actually sends) to Mac key
/// codes, which `KeyLayout` uses for positions.
enum HIDKeys {
    static let keyboardPage: UInt32 = 0x07
    /// Apple's vendor page; usage 0x03 is the fn / Globe key.
    static let appleTopCasePage: UInt32 = 0xFF
    static let fnUsage: UInt32 = 0x03

    /// Mac key codes of the modifier keys (Shift, Control, Option, Command, Caps Lock, fn).
    static let modifierKeyCodes: Set<Int64> = [56, 60, 59, 62, 58, 61, 55, 54, 57, 63]

    static func keyCode(page: UInt32, usage: UInt32) -> Int64? {
        if page == appleTopCasePage { return usage == fnUsage ? 63 : nil }
        guard page == keyboardPage else { return nil }
        return table[usage]
    }

    private static let table: [UInt32: Int64] = {
        var t: [UInt32: Int64] = [:]
        // a–z
        let letters: [Int64] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]
        for (i, code) in letters.enumerated() { t[0x04 + UInt32(i)] = code }
        // 1–9, 0
        let digits: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for (i, code) in digits.enumerated() { t[0x1E + UInt32(i)] = code }
        let rest: [UInt32: Int64] = [
            0x28: 36, 0x29: 53, 0x2A: 51, 0x2B: 48, 0x2C: 49, 0x2D: 27, 0x2E: 24, 0x2F: 33,
            0x30: 30, 0x31: 42, 0x32: 42, 0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47,
            0x38: 44, 0x39: 57,
            // F1–F12
            0x3A: 122, 0x3B: 120, 0x3C: 99, 0x3D: 118, 0x3E: 96, 0x3F: 97, 0x40: 98, 0x41: 100,
            0x42: 101, 0x43: 109, 0x44: 103, 0x45: 111,
            // F13–F15 / Print Screen, Scroll Lock, Pause; navigation block; arrows
            0x46: 105, 0x47: 107, 0x48: 113, 0x49: 114, 0x4A: 115, 0x4B: 116, 0x4C: 117,
            0x4D: 119, 0x4E: 121, 0x4F: 124, 0x50: 123, 0x51: 125, 0x52: 126,
            // Keypad
            0x53: 71, 0x54: 75, 0x55: 67, 0x56: 78, 0x57: 69, 0x58: 76,
            0x59: 83, 0x5A: 84, 0x5B: 85, 0x5C: 86, 0x5D: 87, 0x5E: 88, 0x5F: 89, 0x60: 91,
            0x61: 92, 0x62: 82, 0x63: 65, 0x64: 10, 0x67: 81,
            // Modifiers
            0xE0: 59, 0xE1: 56, 0xE2: 58, 0xE3: 55, 0xE4: 62, 0xE5: 60, 0xE6: 61, 0xE7: 54,
        ]
        t.merge(rest) { $1 }
        return t
    }()
}
