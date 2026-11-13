import SwiftUI
import TrackerCore

struct RecurringView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<Int>()

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "repeat.circle.fill").font(.system(size: 30)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly sessions you see regularly").font(.headline)
                    Text("Each occurrence shows up on the Log page to confirm ✓ or skip ✗ — no retyping. Closing a client's case ends their slots.")
                        .foregroundStyle(.secondary)
                }
            }
            .card()

            Table(model.slots, selection: $selection) {
                TableColumn("When") { s in
                    Text("\(Vocab.weekdays[s.weekday])\(s.time.map { " · \(timeText($0))" } ?? "")").fontWeight(.medium)
                }
                .width(min: 120, ideal: 150)
                TableColumn("Client / group") { s in
                    HStack(spacing: 8) {
                        Avatar(name: s.who, size: 22, isGroup: s.groupId != nil)
                        Text(s.who)
                    }
                }
                .width(min: 110, ideal: 150)
                TableColumn("Type") { s in CategoryDot(category: s.category) }.width(min: 90, ideal: 110)
                TableColumn("Activity") { s in Text(s.activity).lineLimit(1) }.width(min: 140, ideal: 220)
                TableColumn("Duration") { s in Text("\(hoursText(s.minutes)) h").monospacedDigit() }.width(70)
                TableColumn("Site") { s in Text(s.siteName).foregroundStyle(.secondary) }.width(min: 90, ideal: 140)
                TableColumn("Since") { s in Text(Day.medium(s.startDate)).foregroundStyle(.secondary) }.width(min: 90, ideal: 110)
                TableColumn("Status") { s in
                    if s.active { Pill(text: "Active", color: .green) }
                    else { Pill(text: s.endDate.map { "Ended \(Day.medium($0))" } ?? "Paused", color: .secondary) }
                }
                .width(min: 80, ideal: 130)
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                if let id = ids.first, let s = model.slots.first(where: { $0.id == id }) {
                    Button(s.active ? "Pause" : "Resume") { model.run { r in try r.setSlotActive(id: id, !s.active) } }
                    Divider()
                    Button("Delete", role: .destructive) { model.run { r in try r.deleteSlot(id: id) } }
                }
            }
            .overlay {
                if model.slots.isEmpty {
                    ContentUnavailableView {
                        Label("No recurring sessions", systemImage: "repeat")
                    } description: {
                        Text("Set up a weekly client once, then confirm each week with one click.")
                    } actions: {
                        Button("New Recurring Session") { model.showNewSlot = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .card(padding: 0)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(20)
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem {
                Button { model.showNewSlot = true } label: { Label("New Recurring Session", systemImage: "plus") }
                    .disabled(model.sites.isEmpty)
            }
        }
        .sheet(isPresented: $model.showNewSlot) { SlotSheet() }
    }

    private func timeText(_ hhmm: String) -> String {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return hhmm }
        let h = p[0] % 12 == 0 ? 12 : p[0] % 12
        return String(format: "%d:%02d %@", h, p[1], p[0] < 12 ? "AM" : "PM")
    }
}

struct SlotSheet: View {
    @Environment(AppModel.self) private var model
    @State private var draft = EntryDraft()
    var body: some View {
        SheetScaffold(title: "New Recurring Session",
                      subtitle: "A weekly session you can confirm with one click on the Log page.",
                      confirm: "Add", width: 620) {
            let d = draft
            let hhmm = d.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            let comps = Calendar.current.dateComponents([.hour, .minute], from: d.time)
            let time = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
            _ = hhmm
            return model.run { r in
                let i = d.input()
                try r.addSlot(weekday: d.weekday, siteId: i.siteId, activity: i.activity, minutes: i.minutes,
                              category: i.category, modality: i.modality, clientId: i.clientId, groupId: i.groupId,
                              supervisorId: i.supervisorId, time: time, startDate: Day.iso(d.startDate))
            }
        } content: {
            EntryFormView(draft: $draft, mode: .slot).padding(24)
        }
        .onAppear { draft.siteId = model.activeSites.first?.id }
    }
}
