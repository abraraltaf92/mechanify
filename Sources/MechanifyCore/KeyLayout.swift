/// Where a key sits left-to-right on a standard Mac (ANSI) keyboard, used to place
/// its sound in the stereo field. Only the horizontal position is derived; nothing
/// about the key is kept.
public enum KeyLayout {
    /// Keyboard width in key units (Esc/` at the left edge, Delete/Return at the right).
    static let width: Double = 15

    /// Key code → horizontal centre in key units. Unknown keys sit in the middle.
    static let column: [Int64: Double] = [
        // Function row
        53: 0.5, 122: 1.5, 120: 2.5, 99: 3.5, 118: 4.5, 96: 5.5, 97: 6.5,
        98: 7.5, 100: 8.5, 101: 9.5, 109: 10.5, 103: 11.5, 111: 12.5,
        // Number row
        50: 0.5, 18: 1.5, 19: 2.5, 20: 3.5, 21: 4.5, 23: 5.5, 22: 6.5,
        26: 7.5, 28: 8.5, 25: 9.5, 29: 10.5, 27: 11.5, 24: 12.5, 51: 14.0,
        // Top letter row
        48: 0.75, 12: 2.0, 13: 3.0, 14: 4.0, 15: 5.0, 17: 6.0, 16: 7.0,
        32: 8.0, 34: 9.0, 31: 10.0, 35: 11.0, 33: 12.0, 30: 13.0, 42: 14.25,
        // Home row
        57: 0.9, 0: 2.25, 1: 3.25, 2: 4.25, 3: 5.25, 5: 6.25, 4: 7.25,
        38: 8.25, 40: 9.25, 37: 10.25, 41: 11.25, 39: 12.25, 36: 14.0,
        // Bottom letter row
        6: 2.75, 7: 3.75, 8: 4.75, 9: 5.75, 11: 6.75, 45: 7.75, 46: 8.75,
        43: 9.75, 47: 10.75, 44: 11.75,
        // Space and arrows
        49: 7.5, 123: 13.0, 125: 13.75, 126: 13.75, 124: 14.5,
    ]

    /// Stereo position from -1 (far left) to 1 (far right).
    public static func pan(forKeyCode code: Int64) -> Float {
        let x = column[code] ?? width / 2
        return Float(max(-1, min(1, (x - width / 2) / (width / 2))))
    }
}
