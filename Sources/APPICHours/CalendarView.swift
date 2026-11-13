import SwiftUI
import TrackerCore

/// Calendar of every session: month grid, week columns, and a year heat map,
/// with a day panel for details.
struct CalendarView: View {
    enum Mode: String, CaseIterable, Identifiable { case month = "Month", week = "Week", year = "Year"; var id: String { rawValue } }

    @Environment(AppModel.self) private var model
    @AppStorage("calendarMode") private var mode: Mode = .month
    @AppStorage("calendarShowWeekends") private var showWeekends = true
    private var dayCount: Int { showWeekends ? 7 : 5 }
    @State private var anchor = Day.today()          // a date inside the visible period
    @State private var selected = Day.today()
    @State private var showDetail = true
    @State private var hidden: Set<HourCategory> = []
    @State private var whoFilter = ""                // "" = everyone, else a row key ("c12" / "g3")

    // MARK: data

    private var range: (from: String, to: String) {
        switch mode {
        case .month:
            let first = Self.monthStart(anchor)
            let gridStart = Day.add(first, days: -Day.weekday(first))
            return (gridStart, Day.add(gridStart, days: 41))
        case .week:
            let ws = Day.add(anchor, days: -Day.weekday(anchor))
            return (ws, Day.add(ws, days: 6))
        case .year:
            let y = Day.year(anchor)
            return (String(format: "%04d-01-01", y), String(format: "%04d-12-31", y))
        }
    }

    private func keep(_ e: Entry) -> Bool {
        guard !hidden.contains(e.category) else { return false }
        if whoFilter.isEmpty { return true }
        if let c = e.clientId { return whoFilter == "c\(c)" }
        if let g = e.groupId { return whoFilter == "g\(g)" }
        return false
    }

    private func keep(_ o: SlotOccurrence) -> Bool {
        guard !hidden.contains(o.slot.category) else { return false }
        if whoFilter.isEmpty { return true }
        if let c = o.slot.clientId { return whoFilter == "c\(c)" }
        if let g = o.slot.groupId { return whoFilter == "g\(g)" }
        return false
    }

    static func monthStart(_ iso: String) -> String {
        String(format: "%04d-%02d-01", Day.year(iso), Day.month(iso))
    }

    static func addMonths(_ iso: String, _ n: Int) -> String {
        guard let d = Day.date(monthStart(iso)),
              let r = Day.calendar.date(byAdding: .month, value: n, to: d) else { return iso }
        return Day.iso(r)
    }

    private var title: String {
        let d = Day.date(anchor) ?? Date()
        switch mode {
        case .month: return d.formatted(.dateTime.month(.wide).year())
        case .week:
            let (a, b) = range
            return "\(Day.medium(a)) – \(Day.medium(b))"
        case .year: return String(Day.year(anchor))
        }
    }

    // MARK: body

    var body: some View {
        let _ = model.revision
        let (from, to) = range
        let entries = ((try? model.repo?.entries(since: from, until: to)) ?? nil ?? []).filter(keep)
        let byDay = Dictionary(grouping: entries, by: \.date)
        let pending = Dictionary(grouping: model.pending.filter(keep), by: \.date)

        VStack(alignment: .leading, spacing: 14) {
            header(entries)
            switch mode {
            case .month: monthGrid(byDay: byDay, pending: pending)
            case .week: weekColumns(byDay: byDay, pending: pending)
            case .year: yearHeatmap(byDay: byDay)
            }
        }
        .padding(20)
        .navigationTitle("Calendar")
        .navigationSubtitle(title)
        .toolbar {
            ToolbarItemGroup {
                Button { step(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .help("Previous \(mode.rawValue.lowercased()) (⌘←)")
                Button("Today") { anchor = Day.today(); selected = Day.today() }
                    .help("Jump to today")
                Button { step(1) } label: { Label("Next", systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .help("Next \(mode.rawValue.lowercased()) (⌘→)")
            }
            ToolbarItem {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
            }
            ToolbarItem {
                Toggle(isOn: $showWeekends) { Label("Weekends", systemImage: "sun.max") }
                    .help(showWeekends ? "Hide Saturdays and Sundays" : "Show Saturdays and Sundays")
            }
            ToolbarItem {
                Button { showDetail.toggle() } label: { Label("Day details", systemImage: "sidebar.right") }
                    .help("Show or hide the day panel")
            }
        }
        .inspector(isPresented: $showDetail) {
            DayPanel(date: selected,
                     entries: (byDay[selected] ?? []).sorted { $0.id < $1.id },
                     pending: pending[selected] ?? [],
                     inRange: selected >= from && selected <= to)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
    }

    private func step(_ n: Int) {
        switch mode {
        case .month: anchor = Self.addMonths(anchor, n)
        case .week: anchor = Day.add(anchor, days: 7 * n)
        case .year: anchor = String(format: "%04d-%@", Day.year(anchor) + n, String(anchor.dropFirst(5)))
        }
    }

    // MARK: header — period totals and filters

    private func header(_ entries: [Entry]) -> some View {
        // totals only for days inside the period (month view shows a few days of the neighbours)
        let inPeriod: (Entry) -> Bool = { e in
            switch mode {
            case .month: return Self.monthStart(e.date) == Self.monthStart(anchor)
            default: return true
            }
        }
        let counted = entries.filter { !$0.planned && inPeriod($0) }
        let planned = entries.filter { $0.planned && inPeriod($0) }.count
        let total = counted.reduce(0) { $0 + $1.minutes }
        let weekendHidden = showWeekends ? 0 : entries.filter { inPeriod($0) && Day.weekday($0.date) >= 5 }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text("\(counted.count) sessions · \(hoursText(total)) h" + (planned > 0 ? " · \(planned) planned" : ""))
                    .font(.callout).foregroundStyle(.secondary)
                if weekendHidden > 0 {
                    Button { showWeekends = true } label: {
                        Label("\(weekendHidden) on weekends (hidden)", systemImage: "eye.slash")
                    }
                    .buttonStyle(.borderless).font(.callout)
                    .help("Totals include them — click to show weekends")
                }
            }
            // a wrapping row: never demands more width than the window has
            FlowLayout(spacing: 8) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(HourCategory.allCases) { c in
                        let mins = counted.filter { $0.category == c }.reduce(0) { $0 + $1.minutes }
                        ChipButton(title: "\(c.label) \(hoursText(mins))h", isOn: !hidden.contains(c), color: c.color) {
                            if hidden.contains(c) { hidden.remove(c) } else { hidden.insert(c) }
                        }
                        .help(hidden.contains(c) ? "Show \(c.label.lowercased()) sessions" : "Hide \(c.label.lowercased()) sessions")
                    }
                }
            }
            Picker("Client", selection: $whoFilter) {
                Text("Everyone").tag("")
                Section("Clients") {
                    ForEach(model.clients, id: \.rowKey) { c in Text(c.code).tag(c.rowKey) }
                }
                if !model.groups.isEmpty {
                    Section("Groups, families & couples") {
                        ForEach(model.groups, id: \.rowKey) { g in Text(g.name).tag(g.rowKey) }
                    }
                }
            }
            .labelsHidden().fixedSize()
            .help("Show one client's sessions")
            }
        }
    }

    // MARK: month

    private func monthGrid(byDay: [String: [Entry]], pending: [String: [SlotOccurrence]]) -> some View {
        let start = range.from
        let month = Self.monthStart(anchor)
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Vocab.weekdays.prefix(dayCount), id: \.self) { d in
                    Text(d.prefix(3)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
                }
            }
            GeometryReader { geo in
                let cellH = max(78, (geo.size.height - 5 * 6) / 6)
                VStack(spacing: 6) {
                    ForEach(0..<6, id: \.self) { w in
                        HStack(spacing: 6) {
                            ForEach(0..<dayCount, id: \.self) { d in
                                let iso = Day.add(start, days: w * 7 + d)
                                DayCell(date: iso, inPeriod: Self.monthStart(iso) == month,
                                        isSelected: iso == selected, entries: byDay[iso] ?? [],
                                        pending: pending[iso] ?? [], height: cellH) {
                                    selected = iso
                                    showDetail = true
                                }
                            }
                        }
                        .frame(height: cellH)
                    }
                }
            }
        }
    }

    // MARK: week

    private func weekColumns(byDay: [String: [Entry]], pending: [String: [SlotOccurrence]]) -> some View {
        let start = range.from
        return HStack(alignment: .top, spacing: 8) {
            ForEach(0..<dayCount, id: \.self) { d in
                let iso = Day.add(start, days: d)
                let es = (byDay[iso] ?? []).sorted { $0.id < $1.id }
                let ps = pending[iso] ?? []
                let mins = es.filter { !$0.planned }.reduce(0) { $0 + $1.minutes }
                VStack(alignment: .leading, spacing: 8) {
                    Button { selected = iso; showDetail = true } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Vocab.weekdays[d].prefix(3).uppercased()).font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("\(Day.date(iso).map { Day.calendar.component(.day, from: $0) } ?? 0)")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(iso == Day.today() ? Color.accentColor : .primary)
                            }
                            Spacer()
                            if mins > 0 { Text("\(hoursText(mins)) h").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(es) { e in
                                SessionCard(e: e)
                                    .onTapGesture(count: 2) { model.editing = EditRef(id: e.id) }
                                    .onTapGesture { selected = iso; showDetail = true }
                            }
                            ForEach(ps) { o in PendingChip(o: o, large: true) }
                            if es.isEmpty && ps.isEmpty {
                                Text("—").foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 8)
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(iso == selected ? Color.accentColor : Color.secondary.opacity(0.2),
                                  lineWidth: iso == selected ? 2 : 0.5))
            }
        }
    }

    // MARK: year

    private func yearHeatmap(byDay: [String: [Entry]]) -> some View {
        let y = Day.year(anchor)
        let hoursByDay = byDay.mapValues { es in Double(es.filter { !$0.planned }.reduce(0) { $0 + $1.minutes }) / 60 }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 18)], alignment: .leading, spacing: 18) {
                    ForEach(1...12, id: \.self) { m in
                        MiniMonth(year: y, month: m, hours: hoursByDay, selected: selected, showWeekends: showWeekends) { iso in
                            selected = iso
                            anchor = iso
                            mode = .month
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text("Less").font(.caption).foregroundStyle(.secondary)
                    ForEach([0.0, 0.5, 1.5, 3, 5], id: \.self) { h in
                        RoundedRectangle(cornerRadius: 3).fill(MiniMonth.color(h)).frame(width: 14, height: 14)
                    }
                    Text("More hours").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("Click a day to open it in the month view").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Pieces

private func shortDuration(_ minutes: Int) -> String {
    minutes < 60 ? "\(minutes)m" : "\(hoursText(minutes))h"
}

private func label(_ e: Entry) -> String {
    e.who.isEmpty ? e.activity : e.who
}

/// One day in the month grid.
struct DayCell: View {
    let date: String
    let inPeriod: Bool
    let isSelected: Bool
    let entries: [Entry]
    let pending: [SlotOccurrence]
    let height: CGFloat
    let onSelect: () -> Void

    var body: some View {
        let isToday = date == Day.today()
        let counted = entries.filter { !$0.planned }.reduce(0) { $0 + $1.minutes }
        let maxChips = max(1, Int((height - 30) / 19))
        let items: [AnyView] = entries.sorted { $0.id < $1.id }.map { AnyView(SessionChip(e: $0)) }
            + pending.map { AnyView(PendingChip(o: $0)) }
        let weekend = Day.weekday(date) >= 5
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Day.date(date).map { Day.calendar.component(.day, from: $0) } ?? 0)")
                    .font(.callout.weight(isToday ? .bold : .medium)).monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : (inPeriod ? Color.primary : Color.secondary))
                    .frame(minWidth: 22, minHeight: 22)
                    .background(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear), in: Circle())
                Spacer(minLength: 2)
                if counted > 0 {
                    Text("\(hoursText(counted))h").font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(items.prefix(items.count > maxChips ? maxChips - 1 : maxChips).enumerated()), id: \.offset) { _, v in v }
            if items.count > maxChips {
                Text("+\(items.count - maxChips + 1) more").font(.caption2).foregroundStyle(.secondary).padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(weekend ? Color.primary.opacity(0.025) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 0.5))
        .opacity(inPeriod ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onSelect)
    }
}

/// Compact session chip for the month grid.
struct SessionChip: View {
    let e: Entry
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(e.category.color).frame(width: 3)
            if e.planned { Image(systemName: "clock").font(.system(size: 8)).foregroundStyle(.orange) }
            Text(label(e)).fontWeight(.medium).lineLimit(1)
            Spacer(minLength: 2)
            Text(shortDuration(e.minutes)).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.caption2)
        .padding(.vertical, 2).padding(.trailing, 4)
        .frame(height: 16)
        .background(e.category.color.opacity(e.planned ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            if e.planned {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(e.category.color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .help("\(e.category.label) · \(e.activity) · \(AAPI.fmt(e.hours)) h\(e.planned ? " · planned" : "")")
    }
}

/// A recurring session waiting to be confirmed (dashed orange).
struct PendingChip: View {
    let o: SlotOccurrence
    var large = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "repeat").font(.system(size: large ? 10 : 8)).foregroundStyle(.orange)
            Text(o.slot.who).fontWeight(.medium).lineLimit(large ? 2 : 1)
            Spacer(minLength: 2)
            Text(shortDuration(o.slot.minutes)).foregroundStyle(.orange).monospacedDigit()
        }
        .font(large ? .caption : .caption2)
        .padding(.vertical, large ? 6 : 2).padding(.horizontal, 4)
        .frame(minHeight: large ? 0 : 16)
        .overlay(RoundedRectangle(cornerRadius: large ? 8 : 4, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .help("Recurring session — confirm it on the Log page or in the day panel")
    }
}

/// Larger card for the week view and day panel.
struct SessionCard: View {
    let e: Entry
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(e.category.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(label(e)).font(.callout.weight(.semibold)).lineLimit(2)
                    if e.planned { Image(systemName: "clock").font(.caption2).foregroundStyle(.orange).help("Planned") }
                    if e.isBatched { Image(systemName: "square.stack.3d.up.fill").font(.caption2).foregroundStyle(e.category.color).help("Batch-added") }
                }
                Text(e.activity).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 5) {
                    Text("\(AAPI.fmt(e.hours)) h").fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(e.planned ? Color.secondary : Color.primary)
                    Image(systemName: modalityIcon(e.modality)).foregroundStyle(.tertiary)
                    if let n = e.note ?? e.specify ?? e.instruments { Text(n).foregroundStyle(.tertiary).lineLimit(1) }
                }
                .font(.caption2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(e.category.color.opacity(e.planned ? 0.05 : 0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if e.planned {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(e.category.color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .contentShape(Rectangle())
    }
}

/// One month of the year heat map.
struct MiniMonth: View {
    let year: Int
    let month: Int
    let hours: [String: Double]
    let selected: String
    var showWeekends = true
    let onPick: (String) -> Void

    static func color(_ h: Double) -> Color {
        switch h {
        case ..<0.01: return Color.primary.opacity(0.07)
        case ..<1: return Color.accentColor.opacity(0.3)
        case ..<2: return Color.accentColor.opacity(0.5)
        case ..<4: return Color.accentColor.opacity(0.75)
        default: return Color.accentColor
        }
    }

    var body: some View {
        let first = String(format: "%04d-%02d-01", year, month)
        let days = Day.calendar.range(of: .day, in: .month, for: Day.date(first) ?? Date())?.count ?? 30
        // weekends hidden → 5 columns; dropping Sat/Sun keeps each row Mon–Fri
        let visible = (1...days).map { String(format: "%04d-%02d-%02d", year, month, $0) }
            .filter { showWeekends || Day.weekday($0) < 5 }
        let offset = visible.first.map(Day.weekday) ?? 0
        let total = (1...days).reduce(0.0) { $0 + (hours[String(format: "%04d-%02d-%02d", year, month, $1)] ?? 0) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((Day.date(first) ?? Date()).formatted(.dateTime.month(.wide))).font(.headline)
                Spacer()
                if total > 0 { Text("\(AAPI.fmt(total)) h").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 4), count: showWeekends ? 7 : 5), spacing: 4) {
                ForEach(0..<(offset + visible.count), id: \.self) { i in
                    if i < offset {
                        Color.clear.frame(width: 22, height: 22)
                    } else {
                        let iso = visible[i - offset]
                        let h = hours[iso] ?? 0
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Self.color(h))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if iso == Day.today() {
                                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary, lineWidth: 1.5)
                                } else if iso == selected {
                                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 1.5)
                                }
                            }
                            .help("\(Day.medium(iso)) · \(AAPI.fmt(h)) h")
                            .onTapGesture { onPick(iso) }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Inspector: everything on the selected day.
struct DayPanel: View {
    @Environment(AppModel.self) private var model
    let date: String
    let entries: [Entry]
    let pending: [SlotOccurrence]
    let inRange: Bool

    var body: some View {
        let counted = entries.filter { !$0.planned }.reduce(0) { $0 + $1.minutes }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((Day.date(date) ?? Date()).formatted(.dateTime.weekday(.wide)))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    Text(Day.medium(date)).font(.title2.bold())
                    Text("\(entries.count) session\(entries.count == 1 ? "" : "s") · \(hoursText(counted)) h")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button {
                    model.logDraft.date = Day.date(date) ?? Date()
                    model.section = .log
                } label: {
                    Label("Log Session on This Day", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)

                if !pending.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recurring — did these happen?").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        ForEach(pending) { PendingRow(o: $0) }
                    }
                }
                let due = entries.filter { $0.planned && $0.date <= Day.today() }
                if !due.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Planned — did these happen?").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        ForEach(due) { PlannedRow(e: $0) }
                    }
                }

                if entries.isEmpty && pending.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "calendar").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("No sessions").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 30)
                } else {
                    VStack(spacing: 8) {
                        ForEach(entries) { e in
                            SessionCard(e: e)
                                .onTapGesture(count: 2) { model.editing = EditRef(id: e.id) }
                                .contextMenu {
                                    if e.planned && e.date <= Day.today() {
                                        Button("Confirm — It Happened") { model.confirmPlanned(e) }
                                    }
                                    Button("Edit…") { model.editing = EditRef(id: e.id) }
                                    Button("Duplicate to Today") { model.duplicateToToday(e.id) }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        model.run { r in try r.deleteEntry(id: e.id) }
                                    }
                                }
                                .help("Double-click to edit · right-click for more")
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
