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

    static func dayString(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
