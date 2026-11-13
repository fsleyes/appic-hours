import SwiftUI
import TrackerCore

/// Every logged entry, browsable by hour type (like the Log page's Recent box, but complete).
struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("sessionsCategory") private var categoryRaw = ""      // "" = all types
    @State private var activity: String? = nil
    @State private var search = ""
    @State private var selection = Set<Int>()
    @State private var day: String? = nil
    @AppStorage("sessionsHeatmapShown") private var heatmapShown = true
    @AppStorage("sessionsSemester") private var semesterId = 0          // 0 = all time

    private var category: HourCategory? { HourCategory(rawValue: categoryRaw) }

    var body: some View {
        _ = model.revision
        let everything = ((try? model.repo?.entries()) ?? nil) ?? []
        let semester = model.semesters.first { $0.id == semesterId }
        let index = model.semesterIndex
        let all = semester.map { s in everything.filter { index.semester(for: $0)?.id == s.id } } ?? everything
        let ofType = category.map { c in all.filter { $0.category == c } } ?? all
        let shown = ofType.filter { e in
            (activity == nil || e.activity == activity) && (day == nil || e.date == day) && matches(e)
        }
        return VStack(alignment: .leading, spacing: 14) {
            if !model.semesters.isEmpty { semesterBar(semester) }
            HStack(spacing: 12) {
                tile(nil, all)
                ForEach(HourCategory.allCases) { c in tile(c, all.filter { $0.category == c }) }
            }
            HeatmapCard(entries: ofType, color: category?.color ?? .accentColor, selectedDay: $day,
                        shown: $heatmapShown, anchor: semester.map { $0.end ?? Day.today() })
            if category != nil { activityChips(ofType) }
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: category.map { "\($0.label) sessions" } ?? "All sessions",
                          icon: category?.icon ?? "list.bullet.rectangle",
                          subtitle: "\(shown.count) shown · \(hoursText(counted(shown))) h · double-click to edit")
                    .overlay(alignment: .trailing) {
                        if let day {
                            Button { self.day = nil } label: {
                                Pill(text: "Only \(Day.medium(day))", color: .accentColor, icon: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain).help("Show every day again")
                        }
                    }
                EntryTable(entries: shown, selection: $selection, showWho: true)
                    .frame(maxHeight: .infinity)
            }
            .card()
        }
        .padding(20)
        .navigationTitle("Sessions")
        .navigationSubtitle("\(everything.count) entries · \(hoursText(model.totalMinutes)) h total")
        .searchable(text: $search, placement: .toolbar, prompt: "Search client, activity, site, note")
        .onChange(of: categoryRaw) { activity = nil; selection = [] }
        .onChange(of: semesterId) { day = nil; activity = nil; selection = [] }
        .onChange(of: activity) { selection = [] }
        .onChange(of: day) { selection = [] }
    }

    /// Semester chips: All time, then every semester up to the current one (or with sessions).
    private func semesterBar(_ selected: Semester?) -> some View {
        let today = Day.today()
        let list = model.semesters.filter { $0.sessions > 0 || $0.start <= today }
            .filter { $0.sessions > 0 || $0.contains(today) }
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ChipButton(title: "All time", isOn: selected == nil, icon: "infinity") { semesterId = 0 }
                    ForEach(list) { s in
                        ChipButton(title: s.name + (s.contains(today) ? " · now" : ""), isOn: selected?.id == s.id,
                                   icon: "graduationcap") { semesterId = s.id }
                            .help([s.rangeText, s.supervisorName.map { "Supervisor: \($0)" }]
                                .compactMap { $0 }.joined(separator: " · "))
                    }
                }
            }
            if let s = selected {
                HStack(spacing: 6) {
                    Text(s.rangeText)
                    if let sup = s.supervisorName {
                        Text("·"); Image(systemName: "person.crop.circle.badge.checkmark"); Text(sup)
                    }
                    Text("· \(hoursText(s.minutes)) h · \(hoursText(s.directMinutes)) h direct contact")
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// Planned sessions are listed but don't count toward hours.
    private func counted(_ es: [Entry]) -> Int { es.filter { !$0.planned }.reduce(0) { $0 + $1.minutes } }

    private func matches(_ e: Entry) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return [e.who, e.activity, e.siteName, e.note ?? "", e.specify ?? "", e.instruments ?? "", e.modality]
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }

    private func tile(_ c: HourCategory?, _ es: [Entry]) -> some View {
        let selected = category == c
        let color = c?.color ?? .accentColor
        return Button { categoryRaw = c?.rawValue ?? "" } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: c?.icon ?? "square.stack.fill").foregroundStyle(color)
                    Text(c?.label ?? "All types").fontWeight(.medium)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    HoursTicker(minutes: counted(es))
                }
                Text("\(es.count) session\(es.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? color.opacity(0.14) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? color.opacity(0.7) : Color.secondary.opacity(0.25),
                              lineWidth: selected ? 1.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(c.map { "Show every \($0.label.lowercased()) session" } ?? "Show every session")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Activities within the chosen type, biggest first — click one to narrow the table.
    private func activityChips(_ es: [Entry]) -> some View {
        let groups = Dictionary(grouping: es, by: \.activity)
            .map { (name: $0.key, n: $0.value.count, m: counted($0.value)) }
            .sorted { ($0.m, $0.n) > ($1.m, $1.n) }
        let color = category?.color ?? .accentColor
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ChipButton(title: "All activities", isOn: activity == nil, color: color) { activity = nil }
                ForEach(groups, id: \.name) { g in
                    ChipButton(title: "\(g.name) · \(g.n) · \(hoursText(g.m)) h", isOn: activity == g.name, color: color) {
                        activity = activity == g.name ? nil : g.name
                    }
                }
            }
        }
    }
}

// MARK: - Heatmap

/// A year of days as a grid (weeks across, Monday at top), shaded by hours logged.
/// Click a day to show only that day's sessions; ‹ › page back a year at a time.
struct HeatmapCard: View {
    var entries: [Entry]
    var color: Color
    @Binding var selectedDay: String?
    @Binding var shown: Bool
    var anchor: String? = nil               // show the year ending on this date (e.g. a semester's end)
    @State private var page = 0              // 0 = the 52 weeks ending this week; 1 = the 52 before…
    @State private var width: CGFloat = 700

    private let weeks = 52, gap: CGFloat = 3, labelW: CGFloat = 28

    var body: some View {
        let today = Day.today()
        let last = min(anchor ?? today, today)
        let thisSunday = Day.add(last, days: 6 - Day.weekday(last))
        let end = Day.add(thisSunday, days: -7 * weeks * page)
        let start = Day.add(end, days: -7 * weeks + 1)
        var byDay: [String: (m: Int, n: Int)] = [:]
        for e in entries where !e.planned { byDay[e.date, default: (0, 0)].m += e.minutes; byDay[e.date, default: (0, 0)].n += 1 }
        let earliest = entries.filter { !$0.planned }.map(\.date).min()
        let inRange = byDay.filter { $0.key >= start && $0.key <= end }
        let step = max(9, min(26, (width - labelW) / CGFloat(weeks)))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { withAnimation(.snappy) { shown.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(shown ? 90 : 0)).foregroundStyle(.secondary)
                        CardTitle(title: "Activity", icon: "square.grid.3x3.fill",
                                  subtitle: "\(inRange.count) day\(inRange.count == 1 ? "" : "s") with sessions · \(hoursText(inRange.values.reduce(0) { $0 + $1.m })) h")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if shown {
                    Text("\(Day.medium(start)) – \(Day.medium(min(end, today)))").font(.caption).foregroundStyle(.secondary)
                    Button { page += 1 } label: { Image(systemName: "chevron.left") }
                        .disabled(earliest.map { $0 >= start } ?? true).help("Previous year")
                    Button { page -= 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(page == 0).help("Next year")
                }
            }
            .buttonStyle(.borderless)
            if shown {
                grid(start: start, today: today, byDay: byDay, step: step)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                legend
            }
        }
        .card()
        .onChange(of: anchor) { page = 0 }
    }

    private func grid(start: String, today: String, byDay: [String: (m: Int, n: Int)], step: CGFloat) -> some View {
        let cell = step - gap
        return VStack(alignment: .leading, spacing: 4) {
            // month labels where a new month starts
            HStack(spacing: gap) {
                Color.clear.frame(width: labelW - gap, height: 12)
                ForEach(0..<weeks, id: \.self) { w in
                    let monday = Day.add(start, days: 7 * w)
                    let isNewMonth = w == 0 ? Day.month(monday) == Day.month(Day.add(monday, days: 6)) && Int(monday.suffix(2))! <= 7
                                            : Day.month(monday) != Day.month(Day.add(monday, days: -7))
                    Color.clear.frame(width: cell, height: 12)
                        .overlay(alignment: .leading) {
                            if isNewMonth {
                                Text(Day.date(monday)?.formatted(.dateTime.month(.abbreviated)) ?? "")
                                    .font(.caption2).foregroundStyle(.secondary).fixedSize()
                            }
                        }
                }
            }
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { r in
                        Text(r == 0 ? "Mon" : r == 2 ? "Wed" : r == 4 ? "Fri" : "")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .frame(width: labelW - gap, height: cell, alignment: .leading)
                    }
                }
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { r in
                            let d = Day.add(start, days: 7 * w + r)
                            dayCell(d, byDay[d], future: d > today, isToday: d == today, size: cell)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ d: String, _ v: (m: Int, n: Int)?, future: Bool, isToday: Bool, size: CGFloat) -> some View {
        let m = v?.m ?? 0
        let selected = selectedDay == d
        let shape = RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous)
        return shape
            .fill(future ? Color.clear : (m > 0 ? color.opacity(level(m)) : Color.primary.opacity(0.07)))
            .overlay(shape.strokeBorder(selected ? Color.primary : (isToday ? color : Color.clear),
                                        lineWidth: selected ? 2 : 1))
            .frame(width: size, height: size)
            .contentShape(shape)
            .onTapGesture { if m > 0 { selectedDay = selected ? nil : d } }
            .help(future ? "" : "\(Day.medium(d)) · " + (m > 0 ? "\(hoursText(m)) h · \(v!.n) session\(v!.n == 1 ? "" : "s")" : "nothing logged"))
    }

    private func level(_ m: Int) -> Double {
        switch m {
        case ..<60: return 0.3
        case ..<180: return 0.5
        case ..<300: return 0.75
        default: return 1
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Click a day to see just its sessions").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.07)).frame(width: 10, height: 10)
            ForEach([0.3, 0.5, 0.75, 1], id: \.self) { o in
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(o)).frame(width: 10, height: 10)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
                .help("Under 1 h · 1–3 h · 3–5 h · 5 h+")
        }
    }
}
