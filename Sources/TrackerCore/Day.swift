import Foundation

/// Calendar dates are stored as ISO "YYYY-MM-DD" strings.
public enum Day {
    public static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    public static func iso(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func iso(year: Int, month: Int, day: Int) -> String? {
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: d) == day,
              calendar.component(.month, from: d) == month else { return nil }
        return iso(d)
    }

    public static func date(_ iso: String) -> Date? {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func isValid(_ iso: String) -> Bool {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        return Self.iso(year: parts[0], month: parts[1], day: parts[2]) != nil
    }

    public static func today() -> String { iso(Date()) }

    public static func add(_ iso: String, days: Int) -> String {
        guard let d = date(iso), let r = calendar.date(byAdding: .day, value: days, to: d) else {
            return iso
        }
        return Self.iso(r)
    }

    /// Monday = 0 … Sunday = 6
    public static func weekday(_ iso: String) -> Int {
        guard let d = date(iso) else { return 0 }
        return (calendar.component(.weekday, from: d) + 5) % 7
    }

    /// Whole days from `a` to `b` (b - a).
    public static func between(_ a: String, _ b: String) -> Int {
        guard let da = date(a), let db = date(b) else { return 0 }
        return calendar.dateComponents([.day], from: da, to: db).day ?? 0
    }

    public static func year(_ iso: String) -> Int { Int(iso.prefix(4)) ?? 2000 }
    public static func month(_ iso: String) -> Int { Int(iso.dropFirst(5).prefix(2)) ?? 1 }

    /// Excel serial day number (1900 date system).
    public static func excelSerial(_ iso: String) -> Double {
        Double(between("1899-12-30", iso))
    }

    public static func fromExcelSerial(_ n: Double) -> String {
        add("1899-12-30", days: Int(n))
    }

    /// "Thu Nov 06"
    public static func short(_ iso: String) -> String {
        guard let d = date(iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM dd"
        return f.string(from: d)
    }

    /// "Nov 6, 2026"
    public static func medium(_ iso: String) -> String {
        guard let d = date(iso) else { return iso }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}
