import AppKit
import Charts
import SwiftUI
import TrackerCore
import UniformTypeIdentifiers

struct SummaryView: View {
    enum Tab: String, CaseIterable { case aapi = "AAPI Categories", goals = "Goals", demographics = "Demographics",
                                     instruments = "Instruments", sites = "Sites", anticipated = "Anticipated" }

    @Environment(AppModel.self) private var model
    @State private var asOf = Date()
    @State private var tab: Tab = .aapi
    @State private var byDegree: Bool?
    @AppStorage("summaryScope") private var scope: Scope = .everything
    @AppStorage("chartRange") private var range: ChartRange = .w16
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var customTo = Date()

    enum Scope: String, CaseIterable { case direct = "Direct clinical", everything = "Everything" }

    enum ChartRange: String, CaseIterable, Identifiable {
        case w4 = "4 weeks", w8 = "8 weeks", w12 = "12 weeks", w16 = "16 weeks", m6 = "6 months",
             y1 = "1 year", all = "All time", custom = "Custom…"
        var id: String { rawValue }
        var weeks: Int? {
            switch self {
            case .w4: return 4
            case .w8: return 8
            case .w12: return 12
            case .w16: return 16
            case .m6: return 26
            case .y1: return 52
            default: return nil
            }
        }
    }

    private var categories: [HourCategory] {
        scope == .direct ? [.intervention, .assessment] : HourCategory.allCases
    }

    private var showDegrees: Bool { byDegree ?? model.hasTerminalMasters }

    var body: some View {
        let _ = model.revision
        let iso = Day.iso(asOf)
        let summary = model.repo.flatMap { try? AAPI.build($0, asOf: iso) }
        ScrollView {
            if let s = summary {
                VStack(alignment: .leading, spacing: 16) {
                    statCards(s)
                    chartCard
                    Picker("View", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    switch tab {
                    case .aapi:
                        ForEach(scoped(s.sections)) { AAPISectionCard(section: $0, showDegrees: showDegrees) }
                    case .goals:
                        GoalsTab(asOf: iso, directOnly: scope == .direct)
                    case .demographics:
                        AAPISectionCard(section: s.demographics, showDegrees: showDegrees)
                    case .instruments:
                        KVTableCard(title: "Assessment instruments", table: s.instruments,
                                    empty: "Instruments you tick when logging assessments appear here.")
                    case .sites:
                        KVTableCard(title: "Practicum sites", table: s.sites, empty: "Add sites in Setup.")
                    case .anticipated:
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Projection to internship start \(Day.medium(s.anticipated.internshipStart)) (\(AAPI.fmt(s.anticipated.weeksLeft)) weeks away), from your average over the last \(AAPI.fmt(s.anticipated.windowWeeks)) weeks. Adjust for breaks; change the start date in Setup.",
                                  systemImage: "info.circle")
                                .foregroundStyle(.secondary)
                            KVTableCard(title: "Anticipated hours", table: scoped(s.anticipated.table), empty: "")
                        }
                    }
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { controlBar.padding(.horizontal, 20).padding(.top, 10) }
        .navigationTitle("AAPI Summary")
        .navigationSubtitle("as of \(Day.medium(iso))")
        .toolbar {
            ToolbarItemGroup {
                DatePicker("As of", selection: $asOf, displayedComponents: .date)
                    .help("Hours are counted up to and including this date")
                Button("Sept 30 Cutoff") { asOf = Day.date(AAPI.cutoff()) ?? asOf }
                    .help("APPIC counts practicum hours accrued through September 30 of the year you apply")
                Toggle(isOn: Binding(get: { showDegrees }, set: { byDegree = $0 })) {
                    Label("Doctoral / Masters", systemImage: "rectangle.split.3x1")
                }
                .help("Show Doctoral and Terminal Masters columns separately")
                Button { export(iso) } label: { Label("Export to Excel", systemImage: "square.and.arrow.up") }
                    .help("Save every sheet as an .xlsx workbook (⌘E)")
            }
        }
        .onChange(of: model.exportRequest) { _, _ in export(iso) }
    }

    private func statCards(_ s: AAPI.Summary) -> some View {
        let direct = (s.totals["intervention"] ?? 0) + (s.totals["assessment"] ?? 0)
        return HStack(spacing: 12) {
            StatCard(title: "Intervention", value: AAPI.fmt(s.totals["intervention"] ?? 0),
                     icon: HourCategory.intervention.icon, color: HourCategory.intervention.color)
            StatCard(title: "Assessment", value: AAPI.fmt(s.totals["assessment"] ?? 0),
                     icon: HourCategory.assessment.icon, color: HourCategory.assessment.color)
            StatCard(title: "Direct contact", value: AAPI.fmt(direct), icon: "hand.raised.fill", color: .pink)
            if scope == .everything {
                StatCard(title: "Supervision", value: AAPI.fmt(s.totals["supervision"] ?? 0),
                         icon: HourCategory.supervision.icon, color: HourCategory.supervision.color)
                StatCard(title: "Support", value: AAPI.fmt(s.totals["support"] ?? 0),
                         icon: HourCategory.support.icon, color: HourCategory.support.color)
                StatCard(title: "Total", value: AAPI.fmt(s.totals["total"] ?? 0), icon: "sum", color: .indigo)
            }
        }
    }

    /// Liquid Glass control bar that floats over the page as it scrolls.
    private var controlBar: some View {
        HStack(spacing: 14) {
            Picker("Show", selection: $scope) {
                Label("Direct clinical", systemImage: "hand.raised.fill").tag(Scope.direct)
                Label("Everything", systemImage: "square.grid.2x2.fill").tag(Scope.everything)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .help("Direct clinical = intervention + assessment (face-to-face) hours only")
            Spacer(minLength: 8)
            Label("Chart", systemImage: "chart.bar.fill").labelStyle(.titleAndIcon)
                .font(.callout).foregroundStyle(.secondary)
            Picker("Chart range", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden().fixedSize()
            .help("Time frame for the hours-per-week chart")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    /// The chart's date range: ends at the as-of date.
    private func chartRange(asOf: String) -> (from: String, to: String) {
        switch range {
        case .custom:
            let a = Day.iso(customFrom), b = Day.iso(customTo)
            return (min(a, b), max(a, b))
        case .all:
            return (model.repo?.firstEntryDate() ?? asOf, asOf)
        default:
            let monday = Day.add(asOf, days: -Day.weekday(asOf))
            return (Day.add(monday, days: -7 * ((range.weeks ?? 16) - 1)), asOf)
        }
    }

    private var chartCard: some View {
        let (from, to) = chartRange(asOf: Day.iso(asOf))
        let all = model.repo.flatMap { try? AAPI.weekly($0, from: from, to: to) } ?? []
        let points = all.filter { categories.contains($0.category) }
        let (running, overall) = AAPI.runningAverage(all, categories: [.intervention], from: from, to: to)
        let nWeeks = Set(all.map(\.weekStart)).count
        let labelStride = max(1, nWeeks / 8)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(title: "Hours per week", icon: "chart.bar.fill",
                          subtitle: "\(Day.medium(from)) – \(Day.medium(to))")
            }
            if range == .custom {
                HStack(spacing: 8) {
                    DatePicker("From", selection: $customFrom, displayedComponents: .date).fixedSize()
                    DatePicker("To", selection: $customTo, displayedComponents: .date).fixedSize()
                    Text("(the as-of date doesn't apply to a custom range)").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(AAPI.fmt(overall)) h").font(.title3.weight(.semibold)).monospacedDigit()
                    Text("Avg intervention / week").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.primary).frame(width: 18, height: 2)
                    Text("Running average of intervention hours/week").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Week", Day.date(p.weekStart) ?? Date(), unit: .weekOfYear),
                            y: .value("Hours", p.hours))
                        .foregroundStyle(by: .value("Category", p.category.label))
                        .cornerRadius(3)
                        .opacity(0.9)
                }
                ForEach(running) { a in
                    LineMark(x: .value("Week", Day.date(a.weekStart) ?? Date(), unit: .weekOfYear),
                             y: .value("Running avg", a.average))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                        .symbol { Circle().fill(Color.primary).frame(width: nWeeks > 30 ? 0 : 5, height: nWeeks > 30 ? 0 : 5) }
                }
            }
            .chartForegroundStyleScale(domain: categories.map(\.label), range: categories.map(\.color))
            .chartLegend(position: .top, alignment: .leading)
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: labelStride)) { _ in
                AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            } }
            .frame(height: 220)
            .overlay {
                if points.allSatisfy({ $0.hours == 0 }) {
                    Text("No hours in this range").foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    // MARK: direct-only filtering

    private func scoped(_ sections: [AAPI.Section]) -> [AAPI.Section] {
        guard scope == .direct else { return sections }
        return sections.compactMap { sec in
            if sec.title.hasPrefix("SUPERVISION") || sec.title.hasPrefix("SUPPORT") { return nil }
            var sec = sec
            if sec.title == "TOTALS" {
                sec.lines = sec.lines.filter { ["Intervention", "Assessment"].contains($0.label) || $0.label.hasPrefix("Direct contact") }
            } else if sec.title.hasPrefix("MODALITY") {
                // keep only the Intervention and Assessment sub-sections
                var keep = false
                sec.lines = sec.lines.filter { l in
                    if l.level == 0 { keep = ["Intervention", "Assessment"].contains(l.label) }
                    return keep
                }
            }
            return sec
        }
    }

    private func scoped(_ t: AAPI.Table) -> AAPI.Table {
        guard scope == .direct else { return t }
        var t = t
        t.rows = t.rows.filter { r in
            if case .text(let c) = r.first { return c == "Intervention" || c == "Assessment" }
            return true
        }
        return t
    }

    private func export(_ iso: String) {
        guard let repo = model.repo else { return }
        let p = NSSavePanel()
        try? FileManager.default.createDirectory(at: model.config.exportURL, withIntermediateDirectories: true)
        p.directoryURL = model.config.exportURL
        p.nameFieldStringValue = Export.defaultName(asOf: iso)
        p.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try Export.workbook(repo, to: url, asOf: iso)
            let a = NSAlert()
            a.messageText = "Exported \(url.lastPathComponent)"
            a.informativeText = url.deletingLastPathComponent().path
            a.addButton(withTitle: "Open")
            a.addButton(withTitle: "Show in Finder")
            a.addButton(withTitle: "Done")
            switch a.runModal() {
            case .alertFirstButtonReturn: NSWorkspace.shared.open(url)
            case .alertSecondButtonReturn: model.revealInFinder(url)
            default: break
            }
        } catch {
            model.alert = "Export failed: \(error.localizedDescription)"
        }
    }
}

/// "TREATMENT SETTINGS (face-to-face …)" → "Treatment settings (face-to-face …)"
func sentenceCase(_ s: String) -> String {
    let lower = s.lowercased().replacingOccurrences(of: "aapi", with: "AAPI")
    return lower.prefix(1).uppercased() + lower.dropFirst()
}

struct AAPISectionCard: View {
    var section: AAPI.Section
    var showDegrees: Bool

    private var cols: [String] { showDegrees ? AAPI.columns.map(\.label) : ["Total"] }

    var body: some View {
        let showCount = !section.countLabel.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            Text(sentenceCase(section.title)).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Text("")
                    ForEach(cols, id: \.self) { c in
                        Text(showDegrees ? "\(c) h" : "Hours").gridColumnAlignment(.trailing)
                        if showCount { Text(showDegrees ? "#" : section.countLabel).gridColumnAlignment(.trailing) }
                    }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Divider()
                ForEach(section.lines) { line in
                    if line.level == 0 {
                        GridRow {
                            Text(line.label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.top, 6)
                                .gridCellColumns(1 + cols.count * (showCount ? 2 : 1))
                        }
                    } else {
                        if line.isTotal { Divider() }
                        GridRow {
                            Text(line.label).padding(.leading, line.level == 2 ? 14 : 0)
                                .fontWeight(line.isTotal ? .semibold : .regular)
                            ForEach(cols, id: \.self) { c in
                                let cell = line.cells[c] ?? AAPI.Cell()
                                num(line.showHours ? cell.hours : nil, bold: line.isTotal)
                                if showCount {
                                    num(line.showCount ? cell.count.map(Double.init) : nil, bold: line.isTotal)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func num(_ v: Double?, bold: Bool) -> some View {
        if let v {
            Text(AAPI.fmt(v)).monospacedDigit().fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(v == 0 ? .tertiary : .primary)
                .frame(minWidth: 44, alignment: .trailing)
        } else {
            Text("")
        }
    }
}

struct KVTableCard: View {
    var title: String
    var table: AAPI.Table
    var empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if table.rows.isEmpty {
                Text(empty).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            ForEach(Array(table.headers.enumerated()), id: \.offset) { i, h in
                                Text(h).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .gridColumnAlignment(isNumeric(i) ? .trailing : .leading)
                            }
                        }
                        Divider()
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(Array(row.enumerated()), id: \.offset) { i, v in
                                    Text(v.display).monospacedDigit()
                                        .fontWeight(i == 0 ? .medium : .regular)
                                        .foregroundStyle(v == .number(0) ? .tertiary : .primary)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func isNumeric(_ col: Int) -> Bool {
        table.rows.first.map { col < $0.count && { if case .number = $0[col] { return true }; return false }($0) } ?? false
    }
}
