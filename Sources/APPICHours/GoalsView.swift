import Charts
import SwiftUI
import TrackerCore

extension Goals.Metric {
    var color: Color {
        switch self {
        case .intervention: return HourCategory.intervention.color
        case .assessment: return HourCategory.assessment.color
        case .direct: return .pink
        case .supervision: return HourCategory.supervision.color
        case .support: return HourCategory.support.color
        case .total: return .indigo
        }
    }
    var icon: String {
        switch self {
        case .intervention: return HourCategory.intervention.icon
        case .assessment: return HourCategory.assessment.icon
        case .direct: return "hand.raised.fill"
        case .supervision: return HourCategory.supervision.icon
        case .support: return HourCategory.support.icon
        case .total: return "sum"
        }
    }
}

/// Goals tab of the AAPI Summary: hours needed by the APPIC deadline.
struct GoalsTab: View {
    @Environment(AppModel.self) private var model
    let asOf: String
    var directOnly = false

    @State private var goalText: [Goals.Metric: String] = [:]
    @State private var loaded = false

    private var metrics: [Goals.Metric] {
        directOnly ? [.intervention, .assessment, .direct] : Goals.Metric.allCases
    }

    var body: some View {
        let _ = model.revision
        let repo = model.repo
        let deadline = repo.map { Goals.deadline($0, today: asOf) } ?? Day.today()
        let projections = ((try? repo.map { try Goals.all($0, asOf: asOf) }) ?? nil ?? [])
            .filter { metrics.contains($0.metric) }
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(deadline: deadline)
            if projections.isEmpty {
                ContentUnavailableView {
                    Label("No goals yet", systemImage: "target")
                } description: {
                    Text("Enter a goal above — for example your target intervention hours — to see how many hours a week you need before the deadline.")
                }
                .frame(minHeight: 200)
            } else {
                ForEach(projections) { GoalCard(p: $0) }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded, let r = model.repo else { return }
        for m in Goals.Metric.allCases {
            goalText[m] = Goals.goal(r, m).map { AAPI.fmt($0) } ?? ""
        }
        loaded = true
    }

    private func save(_ m: Goals.Metric, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { model.run { r in try Goals.setGoal(r, m, nil) }; return }
        guard let v = Double(t), v >= 0 else { return }   // ignore partial / invalid input
        model.run { r in try Goals.setGoal(r, m, v) }
    }

    private func settingsCard(deadline: String) -> some View {
        let weeks = max(0, Double(Day.between(asOf, deadline)) / 7)
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Goals for the APPIC deadline", icon: "target")
            HStack(spacing: 20) {
                DatePicker("Application deadline",
                           selection: .iso({ deadline }, { v in model.run { r in try Goals.setDeadline(r, v) } }),
                           displayedComponents: .date)
                    .fixedSize()
                Text(weeks > 0 ? "\(AAPI.fmt((weeks * 10).rounded() / 10)) weeks away" : "Deadline has passed")
                    .foregroundStyle(weeks > 0 ? Color.secondary : Color.orange)
                Spacer()
                Picker("Pace from the last", selection: Binding(
                    get: { model.repo.map(Goals.paceWeeks) ?? 8 },
                    set: { v in model.run { r in try Goals.setPaceWeeks(r, v) } })) {
                    Text("4 weeks").tag(4)
                    Text("8 weeks").tag(8)
                    Text("12 weeks").tag(12)
                    Text("26 weeks").tag(26)
                }
                .fixedSize()
                .help("Your current pace is your average hours per week over this window")
            }
            Divider()
            Text("Target hours by the deadline — leave blank for no goal").font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 10) {
                ForEach(metrics) { m in
                    HStack(spacing: 8) {
                        Image(systemName: m.icon).foregroundStyle(m.color).frame(width: 18)
                        Text(m.label).frame(width: 104, alignment: .leading)
                        TextField("—", text: Binding(get: { goalText[m] ?? "" },
                                                     set: { goalText[m] = $0; save(m, $0) }))
                            .textFieldStyle(.roundedBorder).frame(width: 70).multilineTextAlignment(.trailing)
                        Text("h").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
    }
}

struct GoalCard: View {
    let p: Goals.Projection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: p.metric.icon).foregroundStyle(p.metric.color)
                Text(p.metric.label).font(.headline)
                Text("Goal \(AAPI.fmt(p.goal)) h by \(Day.medium(p.deadline))").foregroundStyle(.secondary)
                Spacer()
                status
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: p.progress).tint(p.metric.color)
                Text("\(AAPI.fmt(p.current)) of \(AAPI.fmt(p.goal)) h · \(Int((p.progress * 100).rounded()))%")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                stat("To date", "\(AAPI.fmt(p.current)) h")
                stat("Still needed", p.isMet ? "—" : "\(AAPI.fmt(p.remaining)) h")
                stat("Weeks left", AAPI.fmt(p.weeksLeft))
                stat("Needed per week", p.neededPerWeek.map { "\(AAPI.fmt($0)) h" } ?? "—",
                     highlight: !p.onTrack)
                stat("Your pace (last \(p.paceWeeks) wks)", "\(AAPI.fmt(p.pacePerWeek)) h / wk")
                stat("Projected by deadline", "\(AAPI.fmt(p.projected)) h")
                stat("Goal reached at this pace",
                     p.isMet ? "Already met" : (p.projectedHitDate.map(Day.medium) ?? "Not at current pace"))
                if p.plannedBeforeDeadline > 0 {
                    stat("Planned before deadline", "\(AAPI.fmt(p.plannedBeforeDeadline)) h")
                }
            }

            chart
        }
        .card()
    }

    private var status: some View {
        Group {
            if p.isMet {
                Pill(text: "Goal met", color: .green, icon: "checkmark.seal.fill")
            } else if p.weeksLeft == 0 {
                Pill(text: "Deadline passed · \(AAPI.fmt(p.remaining)) h short", color: .red, icon: "exclamationmark.circle.fill")
            } else if p.onTrack {
                Pill(text: "On track", color: .green, icon: "checkmark.circle.fill")
            } else {
                Pill(text: "Behind · \(AAPI.fmt(p.shortfall)) h short at this pace", color: .orange,
                     icon: "exclamationmark.triangle.fill")
            }
        }
    }

    private func stat(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(highlight ? Color.orange : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        let series: [(Goals.Point.Kind, String)] = [(.actual, "Actual"), (.projected, "At current pace"),
                                                   (.needed, "Needed to hit goal")]
        return Chart {
            ForEach(series, id: \.0) { kind, name in
                ForEach(p.points.filter { $0.kind == kind }) { pt in
                    LineMark(x: .value("Date", Day.date(pt.date) ?? Date()), y: .value("Hours", pt.hours),
                             series: .value("Series", name))
                        .foregroundStyle(by: .value("Series", name))
                        .lineStyle(StrokeStyle(lineWidth: kind == .actual ? 2.5 : 2, dash: kind == .actual ? [] : [5, 4]))
                }
            }
            RuleMark(y: .value("Goal", p.goal))
                .foregroundStyle(Color.green.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal \(AAPI.fmt(p.goal)) h").font(.caption2).foregroundStyle(.green)
                }
            if let d = Day.date(p.deadline) {
                RuleMark(x: .value("Deadline", d))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Deadline").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.1), range: [p.metric.color, p.metric.color.opacity(0.55), Color.secondary])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in
            AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
        } }
        .frame(height: 200)
    }
}
