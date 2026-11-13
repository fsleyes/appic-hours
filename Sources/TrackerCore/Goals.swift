import Foundation

/// Hour goals for the APPIC application deadline, and projections toward them.
public enum Goals {
    public enum Metric: String, CaseIterable, Identifiable, Sendable {
        case intervention, assessment, direct, supervision, support, total
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .intervention: return "Intervention"
            case .assessment: return "Assessment"
            case .direct: return "Direct contact"
            case .supervision: return "Supervision"
            case .support: return "Support"
            case .total: return "Total"
            }
        }
        public var categories: Set<HourCategory> {
            switch self {
            case .intervention: return [.intervention]
            case .assessment: return [.assessment]
            case .direct: return [.intervention, .assessment]
            case .supervision: return [.supervision]
            case .support: return [.support]
            case .total: return Set(HourCategory.allCases)
            }
        }
        var metaKey: String { "goal_\(rawValue)" }
    }

    // MARK: settings (stored in the meta table)

    public static func deadline(_ repo: Repo, today: String = Day.today()) -> String {
        if let v = repo.meta("appic_deadline"), Day.isValid(v) { return v }
        // Default: Nov 1 of this year, or next year once it has passed.
        let y = Day.year(today)
        let thisYear = String(format: "%04d-11-01", y)
        return today <= thisYear ? thisYear : String(format: "%04d-11-01", y + 1)
    }

    public static func setDeadline(_ repo: Repo, _ iso: String) throws {
        try repo.setMeta("appic_deadline", iso)
    }

    public static func goal(_ repo: Repo, _ m: Metric) -> Double? {
        repo.meta(m.metaKey).flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
    }

    public static func setGoal(_ repo: Repo, _ m: Metric, _ hours: Double?) throws {
        if let h = hours, h < 0 { throw ValidationError("A goal can't be negative.") }
        try repo.setMeta(m.metaKey, hours.flatMap { $0 > 0 ? AAPI.fmt($0) : nil })
    }

    public static func paceWeeks(_ repo: Repo) -> Int {
        repo.meta("goal_pace_weeks").flatMap(Int.init).map { max(1, $0) } ?? 8
    }

    public static func setPaceWeeks(_ repo: Repo, _ weeks: Int) throws {
        try repo.setMeta("goal_pace_weeks", String(max(1, weeks)))
    }

    // MARK: projection

    public struct Point: Identifiable, Hashable, Sendable {
        public var id: String { "\(kind)-\(date)" }
        public enum Kind: String, Sendable { case actual, projected, needed }
        public var kind: Kind
        public var date: String
        public var hours: Double
    }

    public struct Projection: Identifiable, Sendable {
        public var id: String { metric.rawValue }
        public var metric: Metric
        public var goal: Double
        public var deadline: String
        public var asOf: String
        public var current: Double              // counted hours up to asOf
        public var remaining: Double            // max(0, goal - current)
        public var weeksLeft: Double            // asOf → deadline, in weeks (0 if passed)
        public var neededPerWeek: Double?       // nil when the deadline has passed or goal is met
        public var pacePerWeek: Double          // average over the last `paceWeeks`
        public var paceWeeks: Int
        public var projected: Double            // current + pace × weeksLeft
        public var plannedBeforeDeadline: Double // planned (not yet counted) hours dated ≤ deadline
        public var projectedHitDate: String?    // when the goal is reached at the current pace
        public var points: [Point]

        public var isMet: Bool { current >= goal }
        public var onTrack: Bool { isMet || projected >= goal }
        public var shortfall: Double { max(0, goal - projected) }
        public var progress: Double { goal > 0 ? min(1, current / goal) : 0 }
    }

    public static func projection(_ repo: Repo, metric: Metric, goal: Double, deadline: String,
                                  asOf: String = Day.today(), paceWeeks: Int = 8) throws -> Projection {
        let cats = metric.categories
        let counted = try repo.entries(until: asOf).filter { !$0.planned && cats.contains($0.category) }
            .map(AAPI.credited)                  // same rounding as the AAPI Summary
        let current = AAPI.round2(Double(counted.reduce(0) { $0 + $1.minutes }) / 60)

        // Pace: average per week over the last `paceWeeks` (or since the first session if sooner).
        let first = counted.map(\.date).min() ?? asOf
        let windowStart = max(first, Day.add(asOf, days: -7 * paceWeeks + 1))
        let windowWeeks = max(1, Double(Day.between(windowStart, asOf) + 1) / 7)
        let recent = counted.filter { $0.date >= windowStart }.reduce(0) { $0 + $1.minutes }
        let pace = Double(recent) / 60 / windowWeeks

        let weeksLeft = max(0, Double(Day.between(asOf, deadline)) / 7)
        let remaining = max(0, goal - current)
        let projected = current + pace * weeksLeft
        let needed: Double? = (remaining > 0 && weeksLeft > 0) ? remaining / weeksLeft : nil
        var hitDate: String?
        if remaining == 0 {
            hitDate = nil
        } else if pace > 0 {
            hitDate = Day.add(asOf, days: Int((remaining / pace * 7).rounded(.up)))
        }

        let planned = try repo.entries(since: Day.add(asOf, days: 1), until: deadline)
            .filter { $0.planned && cats.contains($0.category) }
            .reduce(0) { $0 + $1.minutes }

        // Chart: cumulative actual (weekly), projection at current pace, and the needed path.
        var pts: [Point] = []
        let chartStart = max(first, Day.add(asOf, days: -7 * 52))
        let before = counted.filter { $0.date < chartStart }.reduce(0) { $0 + $1.minutes }
        var cum = Double(before) / 60
        var ws = Day.add(chartStart, days: -Day.weekday(chartStart))
        while ws <= asOf {
            let we = min(Day.add(ws, days: 6), asOf)
            cum += Double(counted.filter { $0.date >= ws && $0.date <= we && $0.date >= chartStart }
                .reduce(0) { $0 + $1.minutes }) / 60
            pts.append(Point(kind: .actual, date: we, hours: AAPI.round2(cum)))
            ws = Day.add(ws, days: 7)
        }
        if weeksLeft > 0 {
            var d = asOf
            while d < deadline {
                let w = Double(Day.between(asOf, d)) / 7
                pts.append(Point(kind: .projected, date: d, hours: AAPI.round2(current + pace * w)))
                d = Day.add(d, days: 7)
            }
            pts.append(Point(kind: .projected, date: deadline, hours: AAPI.round2(projected)))
            if remaining > 0 {
                pts.append(Point(kind: .needed, date: asOf, hours: current))
                pts.append(Point(kind: .needed, date: deadline, hours: goal))
            }
        }

        return Projection(metric: metric, goal: goal, deadline: deadline, asOf: asOf, current: current,
                          remaining: AAPI.round2(remaining), weeksLeft: (weeksLeft * 10).rounded() / 10,
                          neededPerWeek: needed.map(AAPI.round2), pacePerWeek: AAPI.round2(pace),
                          paceWeeks: paceWeeks, projected: AAPI.round2(projected),
                          plannedBeforeDeadline: AAPI.round2(Double(planned) / 60),
                          projectedHitDate: hitDate, points: pts)
    }

    /// Projections for every metric that has a goal set.
    public static func all(_ repo: Repo, asOf: String = Day.today()) throws -> [Projection] {
        let dl = deadline(repo, today: asOf), pw = paceWeeks(repo)
        return try Metric.allCases.compactMap { m in
            guard let g = goal(repo, m) else { return nil }
            return try projection(repo, metric: m, goal: g, deadline: dl, asOf: asOf, paceWeeks: pw)
        }
    }
}
