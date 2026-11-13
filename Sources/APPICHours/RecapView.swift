import SwiftUI
import TrackerCore

/// "Week in review" card. Opens by itself the first time the app comes up after Friday 11:59 PM;
/// the ‹ › arrows page through earlier weeks.
struct RecapSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var friday: String
    @State private var shownMinutes = 0
    @State private var shownTotal = 0
    @State private var grown = false

    init(friday: String) { _friday = State(initialValue: friday) }

    var body: some View {
        _ = model.revision
        let latest = WeekRecap.lastCompletedFriday()
        let first = model.repo?.firstRecapFriday() ?? latest
        let x = (try? model.repo?.weekRecap(friday: friday)) ?? nil
        return VStack(spacing: 0) {
            header(canBack: friday > first, canForward: friday < latest)
            if let x {
                VStack(alignment: .leading, spacing: 18) {
                        if x.isEmpty { emptyWeek } else {
                            hero(x)
                            dayStrip(x)
                            categories(x)
                            let h = highlights(x)
                            if !h.isEmpty { highlightList(h) }
                        }
                }
                .padding(22)
                footer(x)
            }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: friday) { await play(x) }
    }

    // MARK: pieces

    private func header(canBack: Bool, canForward: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Week in review").font(.title2.weight(.bold)).foregroundStyle(.white)
                Text([model.semester(containing: friday)?.name, "\(Day.short(Day.add(friday, days: -6))) – \(Day.short(friday))"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button { friday = Day.add(friday, days: -7) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                .disabled(!canBack).help("Previous week")
            Button { friday = Day.add(friday, days: 7) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                .disabled(!canForward).help("Next week")
        }
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .padding(.horizontal, 22).padding(.vertical, 18)
        .background(LinearGradient(colors: [Color(red: 0.25, green: 0.45, blue: 0.95),
                                            Color(red: 0.45, green: 0.28, blue: 0.86)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func hero(_ x: WeekRecap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HoursTicker(minutes: shownMinutes, font: .system(size: 46, weight: .bold, design: .rounded))
            Text("\(x.sessions) session\(x.sessions == 1 ? "" : "s") · \(x.people) client\(x.people == 1 ? "" : "s") & groups · \(x.byDay.values.filter { $0 > 0 }.count) days")
                .foregroundStyle(.secondary)
            if let line = comparison(x) {
                Pill(text: line.text, color: line.color, icon: line.icon)
            }
        }
    }

    private func dayStrip(_ x: WeekRecap) -> some View {
        let peak = max(x.byDay.values.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(x.days, id: \.self) { d in
                let m = x.byDay[d] ?? 0
                VStack(spacing: 5) {
                    Text(m > 0 ? hoursText(m) : "").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(m == peak && m > 0 ? AnyShapeStyle(Color.accentColor.gradient)
                                                 : AnyShapeStyle(Color.accentColor.opacity(m > 0 ? 0.45 : 0.1)))
                        .frame(height: max(4, (grown ? CGFloat(m) / CGFloat(peak) : 0) * 70))
                    Text(String(Day.short(d).prefix(3))).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .help("\(Day.medium(d)) · \(hoursText(m)) h")
            }
        }
        .frame(height: 110, alignment: .bottom)
    }

    private func categories(_ x: WeekRecap) -> some View {
        VStack(spacing: 8) {
            ForEach(HourCategory.allCases) { c in
                let m = x.byCategory[c] ?? 0
                HStack(spacing: 8) {
                    Image(systemName: c.icon).foregroundStyle(c.color).frame(width: 20)
                    Text(c.label).frame(width: 96, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(Color.primary.opacity(0.06))
                            .overlay(alignment: .leading) {
                                Capsule().fill(c.color.gradient)
                                    .frame(width: grown && m > 0 ? max(6, g.size.width * CGFloat(m) / CGFloat(max(x.minutes, 1))) : 0)
                            }
                    }
                    .frame(height: 8)
                    Text("\(hoursText(m)) h").monospacedDigit().frame(width: 54, alignment: .trailing)
                        .foregroundStyle(m > 0 ? .primary : .secondary)
                }
                .font(.callout)
            }
        }
    }

    private struct Highlight: Identifiable { let id = UUID(); let icon: String; let color: Color; let text: String }

    private func highlights(_ x: WeekRecap) -> [Highlight] {
        var h: [Highlight] = []
        for n in x.totalMilestones { h.append(.init(icon: "flag.checkered", color: .orange, text: "You passed \(n) total hours")) }
        for n in x.directMilestones { h.append(.init(icon: "star.fill", color: .yellow, text: "You passed \(n) direct-contact hours")) }
        if !x.newPeople.isEmpty {
            h.append(.init(icon: "person.badge.plus", color: .blue,
                           text: "First session with \(ListFormatter.localizedString(byJoining: x.newPeople))"))
        }
        if !x.instruments.isEmpty {
            let list = x.instruments.map { $0.count > 1 ? "\($0.name) ×\($0.count)" : $0.name }
            h.append(.init(icon: "testtube.2", color: .purple, text: "Administered \(ListFormatter.localizedString(byJoining: list))"))
        }
        if let (d, m) = x.byDay.max(by: { $0.value < $1.value }), m > 0, x.byDay.values.filter({ $0 > 0 }).count > 1 {
            let weekday = Day.date(d).map { $0.formatted(.dateTime.weekday(.wide)) } ?? d
            h.append(.init(icon: "bolt.fill", color: .pink, text: "Busiest day: \(weekday) · \(hoursText(m)) h"))
        }
        return h
    }

    private func highlightList(_ items: [Highlight]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HIGHLIGHTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(items) { i in
                HStack(spacing: 10) {
                    Image(systemName: i.icon).foregroundStyle(i.color).frame(width: 22)
                    Text(i.text)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyWeek: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf").font(.system(size: 40)).foregroundStyle(.green)
            Text("Nothing logged this week").font(.title3.weight(.semibold))
            Text("If it was a break, enjoy it. If you had sessions, you can add them now.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add Sessions…") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.batchSessions = WhoRef(who: nil) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    private func footer(_ x: WeekRecap) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("ALL TIME").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                HoursTicker(minutes: shownTotal, font: .title3.weight(.semibold))
            }
            Text("· \(hoursText(x.directAfter)) h direct contact").foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.bar)
    }

    // MARK: helpers

    private func comparison(_ x: WeekRecap) -> (text: String, color: Color, icon: String)? {
        guard let avg = x.averageMinutes, avg > 0 else { return nil }
        let diff = x.minutes - avg
        if abs(diff) < 30 { return ("Right around your usual week", .blue, "equal.circle") }
        if diff > 0 { return ("+\(hoursText(diff)) h above your recent average", .green, "arrow.up.right") }
        return ("A lighter week than your recent \(hoursText(avg)) h average", .secondary, "cloud")
    }

    /// Roll the numbers up and grow the bars, a beat after the card appears.
    private func play(_ x: WeekRecap?) async {
        guard let x else { return }
        shownMinutes = 0; shownTotal = x.totalBefore; grown = false
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { grown = true }
        shownMinutes = x.minutes
        try? await Task.sleep(for: .milliseconds(700))
        shownTotal = x.totalAfter
    }
}
