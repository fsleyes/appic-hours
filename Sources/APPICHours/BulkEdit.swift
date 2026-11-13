import SwiftUI
import TrackerCore

/// Entries table with a batch indicator, edit / duplicate / delete, and multi-select
/// bulk editing. Shared by the Log page and client pages.
struct EntryTable: View {
    @Environment(AppModel.self) private var model
    var entries: [Entry]
    @Binding var selection: Set<Int>
    var showWho = true

    var body: some View {
        VStack(spacing: 0) {
            Table(entries, selection: $selection) {
                TableColumn("") { e in
                    HStack(spacing: 3) {
                        if e.planned {
                            Image(systemName: "clock").foregroundStyle(.orange)
                                .help(e.date > Day.today()
                                      ? "Planned — doesn't count yet. You'll confirm it on \(Day.medium(e.date))."
                                      : "Planned — its date has passed. Confirm it under To Confirm on the Log page.")
                        }
                        if e.isBatched {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(e.category.color.opacity(0.85))
                                .help("Batch-added with \(e.batchSize - 1) other session\(e.batchSize == 2 ? "" : "s") — select it to edit the whole batch")
                        }
                    }
                }
                .width(36)
                TableColumn("Date") { e in Text(Day.short(e.date)).monospacedDigit() }
                    .width(min: 80, ideal: 95, max: 110)
                TableColumn("Type") { e in CategoryDot(category: e.category) }
                    .width(min: 90, ideal: 110, max: 130)
                if showWho {
                    TableColumn("Client / group") { e in Text(e.who).fontWeight(.medium) }
                        .width(min: 80, ideal: 120)
                }
                TableColumn("Activity") { e in Text(e.activity).lineLimit(1) }
                    .width(min: 140, ideal: 240)
                TableColumn("Hours") { e in
                    Text(AAPI.fmt(e.hours)).monospacedDigit()
                        .foregroundStyle(e.planned ? .secondary : .primary).italic(e.planned)
                }
                    .width(min: 44, ideal: 54, max: 64)
                TableColumn("Modality") { e in
                    Label(e.modality == "In person" ? "In person" : (e.modality == "Telephone" ? "Phone" : "Video"),
                          systemImage: modalityIcon(e.modality)).labelStyle(.titleAndIcon).foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100, max: 120)
                TableColumn("Site") { e in Text(e.siteName).foregroundStyle(.secondary).lineLimit(1) }
                    .width(min: 80, ideal: 130)
                TableColumn("Note") { e in
                    Text(e.instruments.map { "🧪 \($0)" } ?? e.specify ?? e.note ?? "").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .contextMenu(forSelectionType: Int.self) { ids in menu(ids) } primaryAction: { ids in
                if ids.count == 1, let id = ids.first { model.editing = EditRef(id: id) }
                else if ids.count > 1 { model.bulkEdit = BulkRef(ids: Array(ids)) }
            }
            .overlay {
                if entries.isEmpty {
                    EmptyHint(title: "No sessions yet", icon: "tray", message: "Sessions you log will show up here.")
                }
            }
            // keep the last rows reachable above the floating bar
            .contentMargins(.bottom, floatingBar ? 64 : 0, for: .scrollContent)
            .overlay(alignment: .bottom) {
                Group {
                    if selection.count > 1 {
                        selectionBar
                    } else if let id = selection.first, let e = entries.first(where: { $0.id == id }), e.isBatched,
                              let b = e.batchId {
                        batchBar(e, b)
                    }
                }
                .padding(.bottom, 12).padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.snappy(duration: 0.25), value: selection)
        }
    }

    private var floatingBar: Bool {
        if selection.count > 1 { return true }
        guard let id = selection.first else { return false }
        return entries.first { $0.id == id }?.isBatched ?? false
    }

    @ViewBuilder
    private func menu(_ ids: Set<Int>) -> some View {
        if ids.count == 1, let id = ids.first {
            if let e = entries.first(where: { $0.id == id }), e.planned, e.date <= Day.today() {
                Button("Confirm — It Happened") { model.confirmPlanned(e) }
                Divider()
            }
            Button("Edit…") { model.editing = EditRef(id: id) }
            Button("Duplicate to Today") { model.duplicateToToday(id) }
            if let e = entries.first(where: { $0.id == id }), e.isBatched, let b = e.batchId {
                Divider()
                Button("Select Whole Batch (\(e.batchSize))") { selection = Set(batchIds(b)) }
                Button("Edit Whole Batch (\(e.batchSize) sessions)…") { model.bulkEdit = BulkRef(ids: batchIds(b)) }
            }
            Divider()
        } else if ids.count > 1 {
            Button("Edit \(ids.count) Sessions…") { model.bulkEdit = BulkRef(ids: Array(ids)) }
            Divider()
        }
        if !ids.isEmpty {
            Button(ids.count == 1 ? "Delete" : "Delete \(ids.count) Sessions", role: .destructive) { delete(ids) }
        }
    }

    /// Shown when one session from a batch is selected — makes batch editing discoverable.
    private func batchBar(_ e: Entry, _ batchId: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(e.category.color)
            Text("Part of a batch of \(e.batchSize) sessions added together").fontWeight(.medium)
            Spacer()
            // no glass-on-glass: plain links + one solid capsule on the glass bar
            Button("Select All \(e.batchSize)") { selection = Set(batchIds(batchId)) }
                .buttonStyle(.borderless)
            Button { model.bulkEdit = BulkRef(ids: batchIds(batchId)) } label: {
                Label("Edit Batch…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(e.category.color)
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: .capsule)            // Liquid Glass: floats over the list
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }

    private var selectionBar: some View {
        let picked = entries.filter { selection.contains($0.id) }
        let mins = picked.reduce(0) { $0 + $1.minutes }
        return HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            Text("\(selection.count) selected · \(hoursText(mins)) h").fontWeight(.medium)
            Spacer()
            Button("Deselect") { selection = [] }
                .buttonStyle(.borderless)
            Button("Delete", role: .destructive) { delete(selection) }
                .buttonStyle(.borderless).foregroundStyle(.red)
            Button { model.bulkEdit = BulkRef(ids: Array(selection)) } label: {
                Label("Edit \(selection.count) Sessions…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: .capsule)            // Liquid Glass: floats over the list
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
    }

    private func batchIds(_ b: String) -> [Int] { ((try? model.repo?.batchEntryIds(b)) ?? nil) ?? [] }

    private func delete(_ ids: Set<Int>) {
        model.run { r in try r.db.transaction { for id in ids { try r.deleteEntry(id: id) } } }
        model.showToast("Deleted \(ids.count) session\(ids.count == 1 ? "" : "s")")
        selection = []
    }
}

// MARK: - Bulk edit

/// Change chosen fields on many sessions at once. Unticked fields are left alone.
struct BulkEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ids: [Int]

    @State private var entries: [Entry] = []
    @State private var changeMinutes = false
    @State private var minutes = 60
    @State private var changeActivity = false
    @State private var activity = ""
    @State private var changeWho = false
    @State private var who: Who?
    @State private var changeSite = false
    @State private var siteId: Int?
    @State private var changeModality = false
    @State private var modality = Vocab.defaultModality
    @State private var changePurpose = false
    @State private var purpose = "Clinical"
    @State private var changeNote = false
    @State private var note = ""
    @State private var changeShift = false
    @State private var shift = 0
    @State private var loaded = false

    private var category: HourCategory? { common(\.category) }
    private var commonWho: Who? {
        let ws = Set(entries.map { e -> String in e.clientId.map { "c\($0)" } ?? e.groupId.map { "g\($0)" } ?? "-" })
        guard ws.count == 1, let e = entries.first else { return nil }
        if let c = e.clientId { return .client(c) }
        if let g = e.groupId { return .group(g) }
        return nil
    }
    private var anyChange: Bool {
        changeMinutes || changeActivity || changeWho || changeSite || changeModality || changePurpose
            || changeNote || (changeShift && shift != 0)
    }

    private func common<T: Hashable>(_ kp: KeyPath<Entry, T>) -> T? {
        let vals = Set(entries.map { $0[keyPath: kp] })
        return vals.count == 1 ? vals.first : nil
    }

    private func now<T: Hashable>(_ kp: KeyPath<Entry, T>, _ show: (T) -> String) -> String {
        let vals = entries.map { $0[keyPath: kp] }
        var seen: [T] = []
        for v in vals where !seen.contains(v) { seen.append(v) }
        if seen.count == 1 { return "Now: \(show(seen[0]))" }
        return "Now: mixed (\(seen.prefix(3).map(show).joined(separator: ", "))\(seen.count > 3 ? "…" : ""))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit \(ids.count) Sessions").font(.title2.bold())
                Text(header).foregroundStyle(.secondary)
                Text("Tick what to change — everything else stays as it is.").font(.callout).foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding([.horizontal, .top], 24)

            if loaded {
                Form {
                    ChangeRow(title: "Duration", isOn: $changeMinutes, now: now(\.minutes) { "\(hoursText($0)) h" }) {
                        VStack(alignment: .leading, spacing: 6) {
                            FlowLayout(spacing: 6) {
                                ForEach(EntryFormView.presets, id: \.0) { m, label in
                                    ChipButton(title: label, isOn: minutes == m, color: category?.color ?? .accentColor) { minutes = m }
                                }
                            }
                            Stepper(value: $minutes, in: 5...(24 * 60), step: 5) {
                                Text("\(minutes) min · \(hoursText(minutes)) h").monospacedDigit().foregroundStyle(.secondary)
                            }
                            .fixedSize()
                        }
                    }
                    .onChange(of: minutes) { _, _ in changeMinutes = true }

                    if let cat = category {
                        ChangeRow(title: "Activity", isOn: $changeActivity, now: now(\.activity) { $0 }) {
                            Picker("Activity", selection: $activity) {
                                ForEach(activityOptions(cat), id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                        }
                        .onChange(of: activity) { _, _ in if loaded { changeActivity = true } }

                        if cat != .supervision {
                            ChangeRow(title: "Client / group", isOn: $changeWho, now: now(\.who) { $0.isEmpty ? "none" : $0 }) {
                                Picker("Client", selection: $who) {
                                    Text("— No client —").tag(Who?.none)
                                    Section("Clients") {
                                        ForEach(model.clients, id: \.rowKey) { c in Text(c.code).tag(Who?.some(.client(c.id))) }
                                    }
                                    if cat == .intervention {
                                        Section("Groups, families & couples") {
                                            ForEach(model.groups, id: \.rowKey) { g in Text(g.name).tag(Who?.some(.group(g.id))) }
                                        }
                                    }
                                }
                                .labelsHidden()
                            }
                            .onChange(of: who) { _, _ in if loaded { changeWho = true } }
                        }
                    }

                    ChangeRow(title: "Site", isOn: $changeSite, now: now(\.siteName) { $0 }) {
                        Picker("Site", selection: $siteId) {
                            ForEach(model.sites) { Text($0.name).tag(Int?.some($0.id)) }
                        }
                        .labelsHidden()
                    }
                    .onChange(of: siteId) { _, _ in if loaded { changeSite = true } }

                    ChangeRow(title: "Modality", isOn: $changeModality, now: now(\.modality) { $0 }) {
                        Picker("Modality", selection: $modality) {
                            ForEach(Vocab.modalities, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    .onChange(of: modality) { _, _ in if loaded { changeModality = true } }

                    if category == .assessment {
                        ChangeRow(title: "Purpose", isOn: $changePurpose, now: now(\.purpose) { $0 ?? "—" }) {
                            Picker("Purpose", selection: $purpose) {
                                ForEach(Vocab.assessmentPurposes, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().fixedSize()
                        }
                        .onChange(of: purpose) { _, _ in if loaded { changePurpose = true } }
                    }

                    ChangeRow(title: "Move dates", isOn: $changeShift,
                              now: "Now: \(dateRange)") {
                        Stepper(value: $shift, in: -60...60) {
                            Text(shift == 0 ? "No change" : "\(shift > 0 ? "+" : "")\(shift) day\(abs(shift) == 1 ? "" : "s") each")
                                .monospacedDigit()
                        }
                        .fixedSize()
                    }
                    .onChange(of: shift) { _, _ in changeShift = true }

                    ChangeRow(title: "Note", isOn: $changeNote, now: now(\.noteText) { $0.isEmpty ? "none" : $0 }) {
                        TextField("Note", text: $note, prompt: Text("New note for all — leave empty to clear"))
                            .textFieldStyle(.roundedBorder)
                    }
                    .onChange(of: note) { _, _ in changeNote = true }
                }
                .formStyle(.grouped)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Update \(ids.count) Session\(ids.count == 1 ? "" : "s")") { save() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!anyChange)
            }
            .padding(20)
        }
        .frame(width: 720, height: 640)
        .onAppear(perform: load)
    }

    private var header: String {
        let whoText = commonWho.map { model.label($0) } ?? "\(Set(entries.map(\.who)).count) clients/groups"
        let mins = entries.reduce(0) { $0 + $1.minutes }
        return "\(whoText) · \(dateRange) · \(hoursText(mins)) h total"
    }

    private var dateRange: String {
        let ds = entries.map(\.date).sorted()
        guard let a = ds.first, let b = ds.last else { return "" }
        return a == b ? Day.medium(a) : "\(Day.medium(a)) – \(Day.medium(b))"
    }

    private func activityOptions(_ cat: HourCategory) -> [String] {
        var d = EntryDraft()
        d.category = cat
        d.who = changeWho ? who : commonWho
        var opts = model.activities(for: d)
        if !opts.contains(activity) && !activity.isEmpty { opts.insert(activity, at: 0) }
        return opts
    }

    private func load() {
        entries = ids.compactMap { try? model.repo?.entry($0) ?? nil }
        guard let first = entries.first else { return }
        minutes = common(\.minutes) ?? first.minutes
        activity = common(\.activity) ?? first.activity
        who = commonWho
        siteId = common(\.siteId) ?? first.siteId
        modality = common(\.modality) ?? first.modality
        purpose = (common(\.purpose) ?? first.purpose) ?? "Clinical"
        note = common(\.noteText) ?? ""
        // Prefilling fired onChange — start with nothing ticked.
        DispatchQueue.main.async {
            changeMinutes = false; changeActivity = false; changeWho = false; changeSite = false
            changeModality = false; changePurpose = false; changeNote = false; changeShift = false
            loaded = true
        }
    }

    private func save() {
        var ch = EntryChanges()
        if changeMinutes { ch.minutes = minutes }
        if changeActivity { ch.activity = activity }
        if changeWho { ch.who = .some(who) }
        if changeSite { ch.siteId = siteId }
        if changeModality { ch.modality = modality }
        if changePurpose { ch.purpose = purpose }
        if changeNote { ch.note = .some(note.isEmpty ? nil : note) }
        if changeShift && shift != 0 { ch.shiftDays = shift }
        guard let r = model.repo else { return }
        var before: [Int: EntryInput] = [:]
        for e in entries { before[e.id] = EntryInput(entry: e, instrumentIds: (try? r.entryInstrumentIds(e.id)) ?? []) }
        if model.run({ r in try r.updateEntries(ids: ids, ch) }) {
            model.showToast("Updated \(ids.count) session\(ids.count == 1 ? "" : "s")", restore: before)
            dismiss()
        }
    }
}

extension Entry { var noteText: String { note ?? "" } }

/// A field with a "change this" checkbox and the current value(s) underneath.
struct ChangeRow<Content: View>: View {
    var title: String
    @Binding var isOn: Bool
    var now: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(title, isOn: $isOn).toggleStyle(.checkbox).labelsHidden().padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).fontWeight(isOn ? .semibold : .regular)
                    Spacer()
                    Text(now).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                content.opacity(isOn ? 1 : 0.55)
            }
        }
        .padding(.vertical, 2)
    }
}
