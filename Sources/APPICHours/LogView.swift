import SwiftUI
import TrackerCore

struct LogView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<Int>()

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BannerView()
                HStack(alignment: .top, spacing: 16) {
                    newSessionCard.frame(minWidth: 560, maxWidth: 660)
                    VStack(spacing: 16) {
                        PendingCard()
                        WeekCard()
                    }
                    .frame(minWidth: 280, maxWidth: .infinity)
                }
                recentCard
            }
            .padding(20)
        }
        .navigationTitle("Log")
        .navigationSubtitle("\(model.totalCount) entries · \(hoursText(model.totalMinutes)) h total")
        .toolbar {
            ToolbarItem {
                Button { model.batchSessions = WhoRef(who: model.logDraft.who) } label: {
                    Label("Batch Add Sessions", systemImage: "calendar.badge.plus")
                }
                .help("Add several sessions for one client at once")
            }
        }
    }

    private var newSessionCard: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            CardTitle(title: "New Session", icon: "plus.circle.fill")
            EntryFormView(draft: $model.logDraft, mode: .log)
            HStack {
                Text("⏎ to log").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    var d = model.logDraft
                    if model.log(&d) { model.logDraft = d }
                } label: {
                    Label("Log Session", systemImage: "checkmark")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.logDraft.category.color)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.sites.isEmpty)
            }
        }
        .card(padding: 20)
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Recent", icon: "clock.arrow.circlepath",
                      subtitle: "double-click to edit · right-click for more")
            EntryTable(entries: model.recent, selection: $selection, showWho: true)
                .frame(height: 360)
        }
        .card()
    }
}

struct BannerView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let msgs = model.bannerMessages
        if !msgs.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: model.sites.isEmpty ? "sparkles" : "bell.badge.fill")
                    .foregroundStyle(.orange)
                Text(msgs.joined(separator: "   ")).font(.callout)
                Spacer()
                if model.sites.isEmpty {
                    Button("Open Setup") { model.section = .setup }.buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct PendingCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let items = model.toConfirm
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(title: "To Confirm", icon: "checklist")
                if !items.isEmpty { Pill(text: "\(items.count)", color: .orange) }
            }
            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All caught up").fontWeight(.medium)
                        Text(model.upcomingPlanned > 0
                             ? "\(model.upcomingPlanned) planned session\(model.upcomingPlanned == 1 ? "" : "s") coming up — they'll appear here on their date."
                             : "Recurring and planned sessions appear here once their date arrives.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(items.prefix(8)) { item in
                        switch item {
                        case .slot(let o): PendingRow(o: o)
                        case .planned(let e): PlannedRow(e: e)
                        }
                        if item.id != items.prefix(8).last?.id { Divider() }
                    }
                }
                if items.count > 8 {
                    Text("+ \(items.count - 8) more").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("✓ counts it · ✗ didn't happen").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if items.count > 1 {
                        Button("All Happened") { model.confirmAll() }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .card()
    }
}

/// A planned (future-dated) session whose date has arrived.
struct PlannedRow: View {
    @Environment(AppModel.self) private var model
    var e: Entry
    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: e.who.isEmpty ? e.category.label : e.who, size: 26, isGroup: e.groupId != nil)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(e.who.isEmpty ? e.activity : e.who).fontWeight(.medium)
                    Image(systemName: "clock").font(.caption).foregroundStyle(.orange).help("Planned session")
                }
                Text("\(Day.short(e.date)) · \(AAPI.fmt(e.hours)) h · \(e.activity)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { model.confirmPlanned(e) } label: {
                Image(systemName: "checkmark").fontWeight(.semibold).frame(width: 22, height: 22)
            }
            .buttonStyle(.glassProminent).tint(.green).buttonBorderShape(.circle)
            .help("It happened — count it")
            Button { model.dropPlanned(e) } label: {
                Image(systemName: "xmark").frame(width: 22, height: 22)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .help("Didn't happen — remove it")
        }
        .padding(.vertical, 6)
    }
}

struct PendingRow: View {
    @Environment(AppModel.self) private var model
    var o: SlotOccurrence
    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: o.slot.who, size: 26, isGroup: o.slot.groupId != nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(o.slot.who).fontWeight(.medium)
                Text("\(Day.short(o.date)) · \(hoursText(o.slot.minutes)) h · \(o.slot.activity)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { model.confirm(o) } label: {
                Image(systemName: "checkmark").fontWeight(.semibold).frame(width: 22, height: 22)
            }
            .buttonStyle(.glassProminent).tint(.green).buttonBorderShape(.circle)
            .help("It happened — log it")
            Button { model.skip(o) } label: {
                Image(systemName: "xmark").frame(width: 22, height: 22)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .help("Cancelled / no-show — don't ask again")
        }
        .padding(.vertical, 6)
    }
}

struct WeekCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let monday = Day.add(Day.today(), days: -Day.weekday(Day.today()))
        let week = model.recent.filter { !$0.planned && $0.date >= monday && $0.date <= Day.today() }
        let total = week.reduce(0) { $0 + $1.minutes }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(title: "This Week", icon: "calendar")
                HoursTicker(minutes: total, font: .title3.weight(.semibold))
            }
            ForEach(HourCategory.allCases) { c in
                let m = week.filter { $0.category == c }.reduce(0) { $0 + $1.minutes }
                HStack(spacing: 8) {
                    Circle().fill(c.color).frame(width: 8, height: 8)
                    Text(c.label).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(hoursText(m)) h").monospacedDigit()
                }
                .font(.callout)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(HourCategory.allCases) { c in
                        let m = week.filter { $0.category == c }.reduce(0) { $0 + $1.minutes }
                        if m > 0 {
                            Rectangle().fill(c.color.gradient)
                                .frame(width: max(4, geo.size.width * CGFloat(m) / CGFloat(max(total, 1))))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .frame(height: 8)
            Button { model.showRecap() } label: { Label("Last week's recap", systemImage: "sparkles") }
                .buttonStyle(.borderless).font(.callout)
                .help("Open the recap of the last finished week (Saturday–Friday)")
        }
        .card()
    }
}
