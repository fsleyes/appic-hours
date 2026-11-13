import Foundation

/// AAPI rollup: turns session-level entries into the AAPI categories.
/// Columns are hours and # distinct clients (or groups/families/couples) for
/// Doctoral, Terminal Masters and Total.
public enum AAPI {
    public static let columns: [(degree: String?, label: String)] = [
        ("Doctoral", "Doctoral"), ("Terminal Masters", "Terminal Masters"), (nil, "Total"),
    ]

    public struct Cell: Hashable, Sendable {
        public var hours: Double?
        public var count: Int?
        public init(hours: Double? = nil, count: Int? = nil) { self.hours = hours; self.count = count }
    }

    public struct Line: Identifiable, Hashable, Sendable {
        public var id = UUID()
        public var label: String
        public var level: Int = 1          // 0 = heading, 1 = item, 2 = sub-item
        public var cells: [String: Cell] = [:]
        public var showHours = true
        public var showCount = true
        public var isTotal = false
    }

    public struct Section: Identifiable, Hashable, Sendable {
        public var id = UUID()
        public var title: String
        public var lines: [Line] = []
        public var countLabel = "# Clients"
    }

    public enum Value: Hashable, Sendable {
        case text(String), number(Double)
        public var display: String {
            switch self {
            case .text(let s): return s
            case .number(let n): return fmt(n)
            }
        }
    }

    public struct Table: Hashable, Sendable {
        public var headers: [String]
        public var rows: [[Value]]
    }

    public struct Anticipated: Hashable, Sendable {
        public var internshipStart: String
        public var weeksLeft: Double
        public var windowWeeks: Double
        public var table: Table
    }

    public struct SpecifyNote: Hashable, Sendable {
        public var date, activity, specify, degree: String
        public var hours: Double
    }

    public struct Summary: Sendable {
        public var asOf: String
        public var sections: [Section]
        public var demographics: Section
        public var instruments: Table
        public var sites: Table
        public var anticipated: Anticipated
        public var totals: [String: Double]
        public var nEntries: Int
        public var specifyNotes: [SpecifyNote]
    }

    // MARK: helpers

    public static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
    static func hours(_ minutes: Int) -> Double { round2(Double(minutes) / 60) }

    /// APPIC: round the time spent on each activity up to the next 15 minutes (50 min → 1.00 h).
    /// (AAPI Practicum Hours Tracking Guide, Sept 2026, "Practicum Hour Definition".)
    public static func credited(_ minutes: Int) -> Int { minutes <= 0 ? 0 : (minutes + 14) / 15 * 15 }
    public static func credited(_ e: Entry) -> Entry { var c = e; c.minutes = credited(e.minutes); return c }

    /// APPIC: only hours accrued through September 30 of the application year count.
    public static func cutoff(today: String = Day.today()) -> String { "\(Day.year(today))-09-30" }

    /// 1.5 → "1.5", 2.0 → "2", 0.8333 → "0.83"
    public static func fmt(_ x: Double) -> String {
        let r = round2(x)
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    private static func who(_ e: Entry) -> String? {
        if let c = e.clientId { return "c\(c)" }
        if let g = e.groupId { return "g\(g)" }
        return nil
    }

    private static func heading(_ label: String) -> Line {
        Line(label: label, level: 0, showHours: false, showCount: false)
    }

    private static func line(_ entries: [Entry], _ label: String, level: Int = 1, isTotal: Bool = false,
                             key: ((Entry) -> String?)? = nil, _ pred: (Entry) -> Bool) -> Line {
        var l = Line(label: label, level: level, showCount: key != nil, isTotal: isTotal)
        for (deg, col) in columns {
            let es = entries.filter { pred($0) && (deg == nil || $0.degree == deg) }
            let mins = es.reduce(0) { $0 + $1.minutes }
            var count: Int?
            if let key { count = Set(es.compactMap(key)).count }
            l.cells[col] = Cell(hours: hours(mins), count: count)
        }
        return l
    }

    // MARK: build

    public static func build(_ repo: Repo, asOf: String = Day.today()) throws -> Summary {
        // planned (unconfirmed) sessions never count
        let entries = try repo.db.query("SELECT * FROM entry_full WHERE date <= ? AND planned = 0 ORDER BY date", [asOf])
            .map(Entry.init).map(credited)       // AAPI hours: each activity rounded up to 15 minutes
        let L = { (label: String, level: Int, isTotal: Bool, key: ((Entry) -> String?)?, pred: (Entry) -> Bool) in
            line(entries, label, level: level, isTotal: isTotal, key: key, pred)
        }
        func act(_ name: String) -> (Entry) -> Bool {
            { $0.category == .intervention && $0.activity == name }
        }

        // Intervention
        var inter = Section(title: "INTERVENTION")
        for (head, services) in Vocab.interventionSections {
            if services == [Vocab.individualTherapy] {
                inter.lines.append(heading(head))
                for age in Vocab.clientAges {
                    inter.lines.append(L(age, 2, false, who) { act(Vocab.individualTherapy)($0) && $0.ageGroup == age })
                }
                inter.lines.append(L("Total Individual Therapy", 2, true, who, act(Vocab.individualTherapy)))
            } else if services == [Vocab.careerCounseling] {
                inter.lines.append(heading(head))
                for (label, ages) in Vocab.careerBuckets {
                    inter.lines.append(L(label, 2, false, who) {
                        act(Vocab.careerCounseling)($0) && ages.contains($0.ageGroup ?? "Unknown age")
                    })
                }
            } else if services == [Vocab.groupCounseling] {
                inter.lines.append(heading(head + "  (# groups)"))
                for age in Vocab.groupAges {
                    inter.lines.append(L(age, 2, false, who) {
                        act(Vocab.groupCounseling)($0) && ($0.ageGroup ?? "Unknown age") == age
                    })
                }
            } else {
                inter.lines.append(heading(head))
                for s in services {
                    var label = s
                    if s == Vocab.familyTherapy { label = "Family Therapy (# families)" }
                    if s == Vocab.couplesTherapy { label = "Couples Therapy (# couples)" }
                    inter.lines.append(L(label, 2, false, who, act(s)))
                }
            }
        }
        inter.lines.append(L("TOTAL INTERVENTION", 1, true, who) { $0.category == .intervention })

        // Assessment
        var assess = Section(title: "ASSESSMENT")
        let isA: (Entry) -> Bool = { $0.category == .assessment }
        assess.lines.append(heading("Test Administration (face-to-face hours)"))
        for t in Vocab.assessmentTypes {
            assess.lines.append(L(t, 2, false, who) { isA($0) && $0.activity == t })
        }
        assess.lines.append(L("Total Assessment", 2, true, who, isA))
        assess.lines.append(heading("By purpose"))
        for p in Vocab.assessmentPurposes {
            assess.lines.append(L(p, 2, false, who) { isA($0) && $0.purpose == p })
        }
        let reports = try repo.reports().filter { $0.date <= asOf }
        for (rtype, head) in [(Vocab.integratedReport, "Integrated Psychological Reports (# reports)"),
                              ("Standard Report", "Other Psychological Reports (# reports)")] {
            assess.lines.append(heading(head))
            let unaged = reports.filter { $0.reportType == rtype && Vocab.ageBand($0.ageGroup) == nil }
            for band in ["Adults", "Children/Adolescents"] + (unaged.isEmpty ? [] : ["Age not set — fix the client's age"]) {
                var l = Line(label: band, level: 2, showHours: false)
                for (deg, col) in columns {
                    let n = reports.filter {
                        $0.reportType == rtype && (Vocab.ageBand($0.ageGroup) ?? "Age not set — fix the client's age") == band
                            && (deg == nil || $0.degree == deg)
                    }.count
                    l.cells[col] = Cell(count: n)
                }
                assess.lines.append(l)
            }
        }

        // Supervision
        var sup = Section(title: "SUPERVISION RECEIVED", countLabel: "")
        let isS: (Entry) -> Bool = { $0.category == .supervision }
        for stype in Vocab.supervisionTypes {
            sup.lines.append(heading(stype))
            for svt in Vocab.supervisorTypes {
                sup.lines.append(L(Vocab.supervisorTypeShort[svt]!, 2, false, nil) {
                    isS($0) && $0.activity == stype && $0.supervisorType == svt
                })
            }
            sup.lines.append(L("Total \(stype)", 2, true, nil) { isS($0) && $0.activity == stype })
        }
        sup.lines.append(L("TOTAL SUPERVISION", 1, true, nil, isS))

        // Support
        var supp = Section(title: "SUPPORT", countLabel: "")
        let isP: (Entry) -> Bool = { $0.category == .support }
        for a in Vocab.supportActivities {
            supp.lines.append(L(a, 1, false, nil) { isP($0) && $0.activity == a })
        }
        supp.lines.append(L("TOTAL SUPPORT", 1, true, nil, isP))

        // Treatment settings
        var sett = Section(title: "TREATMENT SETTINGS (face-to-face intervention + assessment hours)")
        let direct: (Entry) -> Bool = { $0.category == .intervention || $0.category == .assessment }
        for st in Vocab.settingTypes {
            sett.lines.append(L(st, 1, false, who) { direct($0) && $0.settingType == st })
        }

        // Modality
        var mod = Section(title: "MODALITY (hours)", countLabel: "")
        for cat in HourCategory.allCases {
            mod.lines.append(heading(cat.label))
            for m in Vocab.modalities {
                mod.lines.append(L(m, 2, false, nil) { $0.category == cat && $0.modality == m })
            }
        }

        // Totals
        var tot = Section(title: "TOTALS")
        tot.lines = [
            L("Intervention", 1, false, who) { $0.category == .intervention },
            L("Assessment", 1, false, who, isA),
            L("Direct contact (intervention + assessment)", 1, true, who, direct),
            L("Supervision", 1, false, nil, isS),
            L("Support", 1, false, nil, isP),
            L("GRAND TOTAL", 1, true, nil) { _ in true },
        ]
        var totals: [String: Double] = [:]
        for cat in HourCategory.allCases {
            totals[cat.rawValue] = hours(entries.filter { $0.category == cat }.reduce(0) { $0 + $1.minutes })
        }
        totals["total"] = hours(entries.reduce(0) { $0 + $1.minutes })

        return Summary(
            asOf: asOf,
            sections: [tot, inter, assess, sup, supp, sett, mod],
            demographics: try demographics(repo, entries),
            instruments: try instruments(repo, asOf),
            sites: try sites(repo, entries),
            anticipated: anticipated(repo, entries, asOf),
            totals: totals,
            nEntries: entries.count,
            specifyNotes: entries.filter { Vocab.needsSpecify($0.activity) }.map {
                SpecifyNote(date: $0.date, activity: $0.activity, specify: $0.specify ?? "",
                            degree: $0.degree, hours: hours($0.minutes))
            })
    }

    // MARK: demographics — # clients seen (≥1 intervention or assessment entry)

    static func demographics(_ repo: Repo, _ entries: [Entry]) throws -> Section {
        let seen = Set(entries.filter { $0.category == .intervention || $0.category == .assessment }
            .compactMap(\.clientId))
        let clients = try repo.clients().filter { seen.contains($0.id) }
        var sec = Section(title: "CLIENT DEMOGRAPHICS (# clients seen)")

        func countLine(_ label: String, _ pred: (Client) -> Bool) -> Line {
            var l = Line(label: label, level: 2, showHours: false)
            for (deg, col) in columns {
                l.cells[col] = Cell(count: clients.filter { pred($0) && (deg == nil || $0.degree == deg) }.count)
            }
            return l
        }
        let fields: [(String, KeyPath<Client, String?>, [String])] = [
            ("Race / Ethnicity", \.race, Vocab.races),
            ("Gender", \.gender, Vocab.genders),
            ("Sexual Orientation", \.orientation, Vocab.orientations),
        ]
        for (head, kp, values) in fields {
            sec.lines.append(heading(head))
            for v in values { sec.lines.append(countLine(v) { $0[keyPath: kp] == v }) }
            sec.lines.append(countLine("(not recorded)") { ($0[keyPath: kp] ?? "").isEmpty })
        }
        sec.lines.append(heading("Disabilities"))
        for d in Vocab.disabilities { sec.lines.append(countLine(d) { $0.disabilities.contains(d) }) }
        var total = countLine("Total clients seen") { _ in true }
        total.isTotal = true
        sec.lines.append(total)
        return sec
    }

    // MARK: instruments

    static func instruments(_ repo: Repo, _ asOf: String) throws -> Table {
        var headers = ["Instrument"]
        for p in Vocab.assessmentPurposes {
            for band in ["Adults", "Children/Adolescents"] { headers.append("\(p) – \(band)") }
        }
        headers += ["Unknown age", "Total administered", "Reports using it", "Integrated reports using it"]
        var rows: [[Value]] = []
        for inst in try repo.instruments() {
            let adm = try repo.db.query("""
                SELECT e.purpose, c.age_group FROM entry_instrument ei JOIN entry e ON e.id=ei.entry_id
                JOIN client c ON c.id=e.client_id WHERE ei.instrument_id=? AND e.date<=? AND e.planned=0
                """, [inst.id, asOf])
            let reps = try repo.db.query("""
                SELECT r.report_type FROM report_instrument ri JOIN report r ON r.id=ri.report_id
                WHERE ri.instrument_id=? AND r.date<=?
                """, [inst.id, asOf])
            var row: [Value] = [.text(inst.name)]
            for p in Vocab.assessmentPurposes {
                for band in ["Adults", "Children/Adolescents"] {
                    row.append(.number(Double(adm.filter {
                        $0.str("purpose") == p && Vocab.ageBand($0.str("age_group")) == band
                    }.count)))
                }
            }
            row.append(.number(Double(adm.filter { Vocab.ageBand($0.str("age_group")) == nil }.count)))
            row.append(.number(Double(adm.count)))
            row.append(.number(Double(reps.count)))
            row.append(.number(Double(reps.filter { $0.str("report_type") == Vocab.integratedReport }.count)))
            if !adm.isEmpty || !reps.isEmpty { rows.append(row) }
        }
        return Table(headers: headers, rows: rows)
    }

    // MARK: sites

    static func sites(_ repo: Repo, _ entries: [Entry]) throws -> Table {
        var sups: [Int: [String]] = [:]
        for s in try repo.supervisors() {
            if let sid = s.siteId { sups[sid, default: []].append(s.name) }
        }
        for e in entries {
            if let name = e.supervisorName, !(sups[e.siteId] ?? []).contains(name) {
                sups[e.siteId, default: []].append(name)
            }
        }
        var headers = ["Site", "Setting type", "Degree", "Start", "End"]
        headers += HourCategory.allCases.map { "\($0.label) hrs" }
        headers += ["Total hrs", "# Clients", "Supervisors"]
        var rows: [[Value]] = []
        for s in try repo.sites() {
            let es = entries.filter { $0.siteId == s.id }
            var row: [Value] = [.text(s.name), .text(s.settingType), .text(s.degreeProgram),
                                .text(s.startDate ?? ""), .text(s.endDate ?? "")]
            for cat in HourCategory.allCases {
                row.append(.number(hours(es.filter { $0.category == cat }.reduce(0) { $0 + $1.minutes })))
            }
            row.append(.number(hours(es.reduce(0) { $0 + $1.minutes })))
            row.append(.number(Double(Set(es.compactMap(\.clientId)).count)))
            row.append(.text((sups[s.id] ?? []).joined(separator: ", ")))
            rows.append(row)
        }
        return Table(headers: headers, rows: rows)
    }

    // MARK: anticipated

    static func anticipated(_ repo: Repo, _ entries: [Entry], _ asOf: String, windowWeeks: Int = 12) -> Anticipated {
        let start = repo.internshipStart()
        let weeksLeft = max(0, Double(Day.between(asOf, start)) / 7)
        let first = entries.map(\.date).min() ?? asOf
        let windowStart = max(first, Day.add(asOf, days: -7 * windowWeeks))
        let span = max(1, Double(Day.between(windowStart, asOf) + 1) / 7)
        var rows: [[Value]] = []
        for cat in HourCategory.allCases {
            let recent = entries.filter { $0.category == cat && $0.date >= windowStart }.reduce(0) { $0 + $1.minutes }
            let current = hours(entries.filter { $0.category == cat }.reduce(0) { $0 + $1.minutes })
            let weekly = Double(recent) / 60 / span
            let projected = round1(weekly * weeksLeft)
            rows.append([.text(cat.label), .number(current), .number(round2(weekly)), .number(projected),
                         .number(round1(current + projected))])
        }
        return Anticipated(
            internshipStart: start, weeksLeft: round1(weeksLeft), windowWeeks: round1(span),
            table: Table(headers: ["Category", "Hours to date", "Avg hrs/week (recent)",
                                   "Projected additional", "Projected at internship start"], rows: rows))
    }

    // MARK: weekly series for charts (not in the export)

    public struct WeekPoint: Identifiable, Hashable, Sendable {
        public var id: String { "\(weekStart)-\(category.rawValue)" }
        public var weekStart: String
        public var category: HourCategory
        public var hours: Double
    }

    public static func weekly(_ repo: Repo, weeks: Int = 16, asOf: String = Day.today()) throws -> [WeekPoint] {
        let thisMonday = Day.add(asOf, days: -Day.weekday(asOf))
        return try weekly(repo, from: Day.add(thisMonday, days: -7 * (weeks - 1)), to: asOf)
    }

    /// Hours per Monday-starting week for sessions dated `from`…`to` (planned ones excluded).
    public static func weekly(_ repo: Repo, from: String, to: String) throws -> [WeekPoint] {
        guard from <= to else { return [] }
        let first = Day.add(from, days: -Day.weekday(from))
        let entries = try repo.entries(since: from, until: to).filter { !$0.planned }
        var out: [WeekPoint] = []
        var ws = first
        while ws <= to {
            let we = Day.add(ws, days: 6)
            for cat in HourCategory.allCases {
                let mins = entries.filter { $0.category == cat && $0.date >= ws && $0.date <= we }
                    .reduce(0) { $0 + $1.minutes }
                out.append(WeekPoint(weekStart: ws, category: cat, hours: Double(mins) / 60))
            }
            ws = Day.add(ws, days: 7)
        }
        return out
    }

    public struct AveragePoint: Identifiable, Hashable, Sendable {
        public var id: String { weekStart }
        public var weekStart: String
        public var average: Double      // hours per week, from `from` through the end of this week
    }

    /// Running (cumulative) average hours/week for the given categories, plus the overall
    /// average for the whole range. Weeks are measured in days/7 from `from`, so partial
    /// first/last weeks aren't over-counted.
    public static func runningAverage(_ points: [WeekPoint], categories: Set<HourCategory>,
                                      from: String, to: String) -> (points: [AveragePoint], overall: Double) {
        let weeks = Array(Set(points.map(\.weekStart))).sorted()
        var cumulative = 0.0
        var out: [AveragePoint] = []
        for ws in weeks {
            cumulative += points.filter { $0.weekStart == ws && categories.contains($0.category) }
                .reduce(0) { $0 + $1.hours }
            let end = min(Day.add(ws, days: 6), to)
            let elapsed = max(1.0, Double(Day.between(from, end) + 1) / 7)
            out.append(AveragePoint(weekStart: ws, average: cumulative / elapsed))
        }
        let span = max(1.0, Double(Day.between(from, to) + 1) / 7)
        return (out, cumulative / span)
    }
}
