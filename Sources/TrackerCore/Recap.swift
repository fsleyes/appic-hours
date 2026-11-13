import Foundation

/// A look back at one recap week: Saturday through Friday, opening once Friday 11:59 PM has passed.
public struct WeekRecap: Sendable, Equatable {
    public var start: String                 // Saturday
    public var end: String                   // Friday
    public var minutes: Int
    public var sessions: Int
    public var byCategory: [HourCategory: Int]
    public var byDay: [String: Int]          // date → minutes, every day of the week present
    public var people: Int                   // distinct clients + groups seen
    public var newPeople: [String]           // clients/groups whose first session fell in this week
    public var instruments: [(name: String, count: Int)]
    public var averageMinutes: Int?          // weekly average over up to 8 earlier weeks with history
    public var totalBefore: Int, totalAfter: Int     // all-time minutes before / after this week
    public var directBefore: Int, directAfter: Int   // intervention + assessment

    public var days: [String] { (0..<7).map { Day.add(start, days: $0) } }
    public var isEmpty: Bool { sessions == 0 }

    /// Every multiple of `step` hours crossed during the week, for `before`→`after` minutes.
    public static func milestones(_ before: Int, _ after: Int, stepHours: Int) -> [Int] {
        let step = stepHours * 60
        guard after > before, step > 0 else { return [] }
        return stride(from: (before / step + 1) * step, through: after, by: step).map { $0 / 60 }
    }
    public var totalMilestones: [Int] { Self.milestones(totalBefore, totalAfter, stepHours: 50) }
    public var directMilestones: [Int] { Self.milestones(directBefore, directAfter, stepHours: 50) }

    public static func == (a: WeekRecap, b: WeekRecap) -> Bool {
        a.start == b.start && a.minutes == b.minutes && a.sessions == b.sessions && a.totalAfter == b.totalAfter
    }
}

extension WeekRecap {
    /// The Friday of the most recent recap week that has fully ended (strictly before `today`).
    public static func lastCompletedFriday(today: String = Day.today()) -> String {
        let back = (Day.weekday(today) - 4 + 7) % 7          // Friday = 4
        return Day.add(today, days: back == 0 ? -7 : -back)
    }
}

extension Repo {
    public func weekRecap(friday: String) throws -> WeekRecap {
        let start = Day.add(friday, days: -6)
        let rows = try db.query("""
            SELECT date, category, minutes, client_id, group_id FROM entry
            WHERE planned=0 AND date BETWEEN ? AND ?
            """, [start, friday])
        var byCat: [HourCategory: Int] = [:], byDay: [String: Int] = [:]
        var people = Set<String>(), minutes = 0
        for d in 0..<7 { byDay[Day.add(start, days: d)] = 0 }
        for r in rows {
            let m = r.int("minutes") ?? 0
            minutes += m
            if let c = HourCategory(rawValue: r.str("category") ?? "") { byCat[c, default: 0] += m }
            if let d = r.str("date") { byDay[d, default: 0] += m }
            if let c = r.int("client_id") { people.insert("c\(c)") }
            if let g = r.int("group_id") { people.insert("g\(g)") }
        }
        let newPeople = try db.query("""
            SELECT name FROM (
              SELECT c.code AS name, MIN(e.date) AS first FROM entry e JOIN client c ON c.id=e.client_id
              WHERE e.planned=0 GROUP BY c.id
              UNION ALL
              SELECT g.name, MIN(e.date) FROM entry e JOIN client_group g ON g.id=e.group_id
              WHERE e.planned=0 GROUP BY g.id)
            WHERE first BETWEEN ? AND ? ORDER BY first, name
            """, [start, friday]).compactMap { $0.str("name") }
        let instruments = try db.query("""
            SELECT i.name AS name, COUNT(*) AS n FROM entry e
            JOIN entry_instrument ei ON ei.entry_id=e.id JOIN instrument i ON i.id=ei.instrument_id
            WHERE e.planned=0 AND e.date BETWEEN ? AND ? GROUP BY i.id ORDER BY n DESC, i.name
            """, [start, friday]).map { (name: $0.str("name") ?? "", count: $0.int("n") ?? 0) }

        func sum(_ whereSQL: String, _ args: [Any?]) throws -> Int {
            (try db.one("SELECT COALESCE(SUM(minutes),0) AS m FROM entry WHERE planned=0 AND " + whereSQL, args))?
                .int("m") ?? 0
        }
        let direct = "category IN ('intervention','assessment')"
        let totalBefore = try sum("date < ?", [start]), totalAfter = try sum("date <= ?", [friday])
        let directBefore = try sum("date < ? AND " + direct, [start])
        let directAfter = try sum("date <= ? AND " + direct, [friday])

        // Average over the (up to) 8 weeks before this one, counting only weeks after logging began.
        var average: Int? = nil
        if let first = (try db.one("SELECT MIN(date) AS d FROM entry WHERE planned=0"))?.str("d"), first < start {
            let weeks = min(8, max(1, (Day.between(first, start) + 6) / 7))
            average = try sum("date >= ? AND date < ?", [Day.add(start, days: -7 * weeks), start]) / weeks
        }
        return WeekRecap(start: start, end: friday, minutes: minutes, sessions: rows.count, byCategory: byCat,
                         byDay: byDay, people: people.count, newPeople: newPeople, instruments: instruments,
                         averageMinutes: average, totalBefore: totalBefore, totalAfter: totalAfter,
                         directBefore: directBefore, directAfter: directAfter)
    }

    /// Friday of the earliest recap week holding a logged session (for paging back), if any.
    public func firstRecapFriday() -> String? {
        guard let first = (try? db.one("SELECT MIN(date) AS d FROM entry WHERE planned=0"))?.str("d") else { return nil }
        return Day.add(first, days: (4 - Day.weekday(first) + 7) % 7)
    }
}
