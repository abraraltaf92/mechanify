import Foundation

/// How many keys you've pressed today and in total. Counts only: nothing about which keys
/// is ever recorded.
public struct KeyStats: Codable, Equatable {
    /// The local calendar day `today` belongs to, as "yyyy-MM-dd".
    public private(set) var day: String
    public private(set) var today: Int
    public private(set) var total: Int

    public init(day: String = "", today: Int = 0, total: Int = 0) {
        self.day = day
        self.today = today
        self.total = total
    }

    /// Counts one key press made at `date`, starting a fresh daily count after midnight.
    public mutating func recordPress(at date: Date = Date(), calendar: Calendar = .current) {
        rollOver(to: date, calendar: calendar)
        today += 1
        total += 1
    }

    /// Today's count as of `date`: 0 if the stored count is from an earlier day.
    public func today(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        Self.dayString(date, calendar) == day ? today : 0
    }

    public mutating func reset() {
        self = KeyStats()
    }

    private mutating func rollOver(to date: Date, calendar: Calendar) {
        let now = Self.dayString(date, calendar)
        if now != day {
            day = now
            today = 0
        }
    }

    /// Short form for tight spaces: 999, 1.2K, 12.3K, 123K, 1.2M, 1.2B. One decimal while
    /// the number is small enough to need it, never a trailing ".0", always rounded down
    /// so 999,999 shows as 999K rather than jumping ahead to 1M.
    public static func compact(_ n: Int) -> String {
        let value = Double(max(0, n))
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        guard let (size, suffix) = units.first(where: { value >= $0.0 }) else { return String(max(0, n)) }
        let scaled = value / size
        if scaled >= 1000 { return "999T+" }  // beyond any real typing; keeps the width fixed
        let decimals = scaled < 100 ? 1 : 0
        let factor = pow(10, Double(decimals))
        let floored = (scaled * factor).rounded(.down) / factor
        let text = floored == floored.rounded() ? String(Int(floored)) : String(format: "%.1f", floored)
        return text + suffix
    }

    static func dayString(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
