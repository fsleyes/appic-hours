import Foundation

/// A semester runs from its start date to the day before the next semester starts, so every
/// date belongs to exactly one. Start dates are usually the school's first day of classes.
/// Its supervisor is the one set by hand, or else whoever you had the most supervision with.
public struct Semester: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var start: String
    public var end: String?                  // nil = the latest semester, open-ended
    public var supervisorId: Int?            // chosen by hand
    public var autoSupervisorId: Int?        // most supervision sessions in the date range
    public var supervisorName: String?       // effective supervisor's name
    public var minutes = 0, sessions = 0
    public var byCategory: [HourCategory: Int] = [:]

    public var effectiveSupervisorId: Int? { supervisorId ?? autoSupervisorId }
    public var directMinutes: Int { (byCategory[.intervention] ?? 0) + (byCategory[.assessment] ?? 0) }
    public func contains(_ date: String) -> Bool { date >= start && (end.map { date <= $0 } ?? true) }
    /// "Aug 25, 2025 – Jan 11, 2026"
    public var rangeText: String { "\(Day.medium(start)) – " + (end.map(Day.medium) ?? "onward") }
}

/// Assigns sessions to semesters. By date — except a supervision session with the previous or
/// next semester's supervisor goes to that semester (handoffs often overlap by a week or two).
public struct SemesterIndex: Sendable {
    public let semesters: [Semester]          // sorted by start
    public init(_ semesters: [Semester]) { self.semesters = semesters.sorted { $0.start < $1.start } }

    public func index(date: String) -> Int? { semesters.lastIndex { $0.start <= date } }

    public func semesterIndex(date: String, category: HourCategory, supervisorId: Int?) -> Int? {
        guard let i = index(date: date) else {
            // before the first semester: only a supervision session with its supervisor moves in
            if category == .supervision, let s = supervisorId, let f = semesters.first,
               f.effectiveSupervisorId == s { return 0 }
            return nil
        }
        guard category == .supervision, let s = supervisorId else { return i }
        let own = semesters[i].effectiveSupervisorId
        if own == nil || own == s { return i }
        if i > 0, semesters[i - 1].effectiveSupervisorId == s { return i - 1 }
        if i + 1 < semesters.count, semesters[i + 1].effectiveSupervisorId == s { return i + 1 }
        return i
    }

    public func semester(for e: Entry) -> Semester? {
        semesterIndex(date: e.date, category: e.category, supervisorId: e.supervisorId).map { semesters[$0] }
    }
}

extension Repo {
    /// `asOf` limits the counts to sessions on or before that date (the export's cutoff).
    public func semesters(asOf: String? = nil) throws -> [Semester] {
        var list = try db.query("SELECT id, name, start_date, supervisor_id FROM semester ORDER BY start_date")
            .map { r in Semester(id: r.int("id")!, name: r.str("name") ?? "", start: r.str("start_date") ?? "",
                                 supervisorId: r.int("supervisor_id")) }
        for i in list.indices where i + 1 < list.count { list[i].end = Day.add(list[i + 1].start, days: -1) }
        for i in list.indices {
            list[i].autoSupervisorId = try db.one("""
                SELECT supervisor_id AS s FROM entry WHERE planned=0 AND category='supervision'
                AND supervisor_id IS NOT NULL AND date >= ? AND date <= ?
                GROUP BY supervisor_id ORDER BY COUNT(*) DESC, MAX(date) DESC LIMIT 1
                """, [list[i].start, list[i].end ?? "9999-12-31"])?.int("s")
        }
        let names = Dictionary(uniqueKeysWithValues: try db.query("SELECT id, name FROM supervisor")
            .map { ($0.int("id")!, $0.str("name") ?? "") })
        for i in list.indices { list[i].supervisorName = list[i].effectiveSupervisorId.flatMap { names[$0] } }

        let index = SemesterIndex(list)
        for r in try db.query("SELECT date, category, supervisor_id, minutes FROM entry WHERE planned=0 AND date <= ?",
                              [asOf ?? "9999-12-31"]) {
            let cat = HourCategory(rawValue: r.str("category") ?? "") ?? .intervention
            guard let i = index.semesterIndex(date: r.str("date") ?? "", category: cat,
                                              supervisorId: r.int("supervisor_id")) else { continue }
            let m = r.int("minutes") ?? 0
            list[i].minutes += m; list[i].sessions += 1; list[i].byCategory[cat, default: 0] += m
        }
        return list
    }

    @discardableResult
    public func addSemester(name: String, start: String, supervisorId: Int? = nil) throws -> Int {
        let (n, s) = try validSemester(name, start, excluding: nil)
        return try db.run("INSERT INTO semester(name, start_date, supervisor_id) VALUES(?,?,?)", [n, s, supervisorId])
    }

    public func updateSemester(id: Int, name: String, start: String, supervisorId: Int?) throws {
        let (n, s) = try validSemester(name, start, excluding: id)
        try db.run("UPDATE semester SET name=?, start_date=?, supervisor_id=? WHERE id=?", [n, s, supervisorId, id])
    }

    public func deleteSemester(id: Int) throws { try db.run("DELETE FROM semester WHERE id=?", [id]) }

    private func validSemester(_ name: String, _ start: String, excluding id: Int?) throws -> (String, String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        try Self.check(!n.isEmpty, "Give the semester a name, like “Fall 2027”.")
        guard let s = try Self.isoOrNil(start) else { throw ValidationError("Pick a start date.") }
        let clash = try db.one("SELECT name FROM semester WHERE start_date=? AND id IS NOT ?", [s, id])
        try Self.check(clash == nil, "\(clash?.str("name") ?? "Another semester") already starts on \(Day.medium(s)).")
        return (n, s)
    }

    /// Add many semesters at once (e.g. a preset), skipping any whose start date is already used.
    /// Returns how many were added.
    @discardableResult
    public func addSemesters(_ list: [(name: String, start: String)]) throws -> Int {
        try db.transaction {
            var n = 0
            for s in list where try db.one("SELECT 1 FROM semester WHERE start_date=?", [s.start]) == nil {
                try addSemester(name: s.name, start: s.start); n += 1
            }
            return n
        }
    }

    /// A guess for "Add Semester": the term after the latest one, or — with none yet — the term
    /// you're in now. Dates follow a typical US calendar (fall/spring classes start the Monday on
    /// or after Aug 22 / Jan 10, summer around May 13); they're meant to be edited.
    public func suggestedNextSemester(today: String = Day.today()) -> (name: String, start: String) {
        guard let last = try? semesters().last else {
            let y = Day.year(today)
            let candidates = [Self.typicalTerm("Fall", y - 1), Self.typicalTerm("Spring", y),
                              Self.typicalTerm("Summer", y), Self.typicalTerm("Fall", y)]
            return candidates.last { $0.start <= today } ?? candidates[0]
        }
        let parts = last.name.split(separator: " ")
        let year = parts.last.flatMap { Int($0) } ?? Day.year(last.start)
        switch parts.first?.lowercased() {
        case "fall": return Self.typicalTerm("Spring", year + 1)
        case "spring": return Self.typicalTerm("Summer", year)
        default: return Self.typicalTerm("Fall", year)
        }
    }

    public static func typicalTerm(_ season: String, _ year: Int) -> (name: String, start: String) {
        let (month, day) = season == "Spring" ? (1, 10) : season == "Summer" ? (5, 13) : (8, 22)
        var d = Day.iso(year: year, month: month, day: day) ?? "\(year)-01-01"
        if season != "Summer" { d = Day.add(d, days: (7 - Day.weekday(d)) % 7) }
        return ("\(season) \(year)", d)
    }
}

/// Ready-made semester calendars, offered in Setup when you have no semesters yet.
public enum SemesterPreset: CaseIterable, Identifiable, Sendable {
    case temple
    public var id: Self { self }
    public var title: String {
        switch self { case .temple: return "Temple University, Fall 2024 – Summer 2027" }
    }
    /// First day of full-term classes (summer = Summer I), from Temple's registrar academic calendars.
    public var semesters: [(name: String, start: String)] {
        switch self {
        case .temple:
            return [("Fall 2024", "2024-08-26"), ("Spring 2025", "2025-01-13"), ("Summer 2025", "2025-05-15"),
                    ("Fall 2025", "2025-08-25"), ("Spring 2026", "2026-01-12"), ("Summer 2026", "2026-05-13"),
                    ("Fall 2026", "2026-08-24"), ("Spring 2027", "2027-01-11"), ("Summer 2027", "2027-05-12")]
        }
    }
}
