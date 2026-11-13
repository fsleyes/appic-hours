import SwiftUI
import TrackerCore

/// Fields for one session. Used by Log (full), menu-bar quick log (compact), edit,
/// recurring slots and the batch-sessions template.
struct EntryFormView: View {
    enum Mode { case log, quick, edit, slot, batchTemplate }

    @Environment(AppModel.self) private var model
    @Binding var draft: EntryDraft
    var mode: Mode = .log
    var lockCategory = false            // hide the category tabs (e.g. supervision-only sheet)
    @State private var newInstrument = ""
    @State private var addingInstrument = false

    static let presets: [(Int, String)] = [(30, "30m"), (45, "45m"), (50, "50m"), (60, "1h"),
                                           (90, "1.5h"), (120, "2h"), (180, "3h")]

    private var showDate: Bool { mode == .log || mode == .quick || mode == .edit }
    private var showNote: Bool { mode == .log || mode == .edit || mode == .quick }
    private var showAssessmentExtras: Bool { draft.category == .assessment && mode != .slot }
    private var showSpecify: Bool { Vocab.needsSpecify(draft.activity) && mode != .slot }
    private var compact: Bool { mode == .quick }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if !lockCategory { CategoryTabs(selection: $draft.category, compact: compact) }

            if mode == .slot { slotRows }
            if showDate { dateRow }
            if draft.usesWho { whoRow } else { supervisorRow }
            FieldRow(label: "Activity") {
                Picker("Activity", selection: $draft.activity) {
                    ForEach(model.activities(for: draft), id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            if !compact {
                FieldRow(label: "Site") {
                    Picker("Site", selection: $draft.siteId) {
                        if draft.siteId == nil { Text("Choose a site").tag(Int?.none) }
                        ForEach(model.sites) { s in Text(s.name).tag(Int?.some(s.id)) }
                    }
                    .labelsHidden()
                }
            }
            durationRow
            FieldRow(label: "Modality") {
                Picker("Modality", selection: $draft.modality) {
                    ForEach(Vocab.modalities, id: \.self) { m in
                        Label(shortModality(m), systemImage: modalityIcon(m)).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if showAssessmentExtras { assessmentRows }
            if showSpecify {
                FieldRow(label: "Specify") {
                    TextField("Required for “(specify)” categories", text: $draft.specify)
                        .textFieldStyle(.roundedBorder)
                }
            }
            if showNote {
                FieldRow(label: "Note") {
                    TextField("Optional — no identifying details", text: $draft.note)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onChange(of: draft.who) { _, _ in
            var d = draft
            if mode == .edit { model.normalizeActivity(&d) } else { model.applyWhoDefaults(&d) }
            draft = d
        }
        .onChange(of: draft.supervisorId) { _, _ in
            guard mode != .edit else { return }
            var d = draft
            model.applySupervisorDefaults(&d)
            draft = d
        }
        .onChange(of: draft.category) { _, _ in
            var d = draft
            model.normalizeActivity(&d)
            draft = d
        }
        .onAppear {
            var d = draft
            model.normalizeActivity(&d)
            if d.siteId == nil { d.siteId = model.activeSites.first?.id }
            if d != draft { draft = d }
        }
    }

    private func shortModality(_ m: String) -> String {
        ["Telehealth (video)": "Video", "Telephone": "Phone"][m] ?? m
    }

    // MARK: rows

    private var slotRows: some View {
        Group {
            FieldRow(label: "Every") {
                HStack {
                    Picker("Weekday", selection: $draft.weekday) {
                        ForEach(0..<7, id: \.self) { Text(Vocab.weekdays[$0]).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Text("at").foregroundStyle(.secondary)
                    DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)
                        .labelsHidden().fixedSize()
                }
            }
            FieldRow(label: "Starting") {
                DatePicker("Start", selection: $draft.startDate, displayedComponents: .date)
                    .labelsHidden().fixedSize()
            }
        }
    }

    private var dateRow: some View {
        FieldRow(label: "Date") {
            HStack(spacing: 8) {
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                    .labelsHidden().fixedSize()
                let today = Day.today(), iso = Day.iso(draft.date)
                ChipButton(title: "Today", isOn: iso == today, color: draft.category.color) { draft.date = Date() }
                ChipButton(title: "Yesterday", isOn: iso == Day.add(today, days: -1), color: draft.category.color) {
                    draft.date = Day.date(Day.add(today, days: -1)) ?? Date()
                }
            }
        }
    }

    private var whoRow: some View {
        FieldRow(label: draft.category == .support ? "Client" : "Client / group", alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Client", selection: $draft.who) {
                    Text("— No client —").tag(Who?.none)
                    if let w = draft.who, model.isClosed(w) {
                        Text("\(model.label(w))  (closed)").tag(Who?.some(w))
                    }
                    // assessment-category sessions list assessment clients first
                    ForEach(draft.category == .assessment ? [ClientKind.assessment, .therapy] : [.therapy, .assessment]) { kind in
                        let list = model.openClients.filter { $0.kind == kind }
                        if !list.isEmpty {
                            Section(kind == .therapy ? "Therapy clients" : "Assessment clients") {
                                ForEach(list, id: \.rowKey) { c in
                                    Text("\(c.code)   ·  \(c.siteName)").tag(Who?.some(.client(c.id)))
                                }
                            }
                        }
                    }
                    if !model.openGroups.isEmpty && draft.category == .intervention {
                        Section("Groups, families & couples") {
                            ForEach(model.openGroups, id: \.rowKey) { g in
                                Text("\(g.name)   ·  \(g.shortType)").tag(Who?.some(.group(g.id)))
                            }
                        }
                    }
                }
                .labelsHidden()
                if mode == .log || mode == .quick {
                    let recents = model.recentOpen(compact ? 4 : 8)
                    if !recents.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(recents, id: \.self) { w in
                                ChipButton(title: model.label(w), isOn: draft.who == w, color: draft.category.color,
                                           icon: w.groupId != nil ? "person.3.fill" : nil) {
                                    draft.who = (draft.who == w) ? nil : w
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var supervisorRow: some View {
        FieldRow(label: "Supervisor") {
            Picker("Supervisor", selection: $draft.supervisorId) {
                Text("Choose a supervisor").tag(Int?.none)
                ForEach(model.activeSupervisors) { s in Text("\(s.name)  ·  \(s.shortType)").tag(Int?.some(s.id)) }
            }
            .labelsHidden()
        }
    }

    private var durationRow: some View {
        FieldRow(label: "Duration", alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6) {
                    ForEach(Self.presets.prefix(compact ? 5 : 7), id: \.0) { m, label in
                        ChipButton(title: label, isOn: draft.minutes == m, color: draft.category.color) {
                            draft.minutes = m
                        }
                    }
                }
                Stepper(value: $draft.minutes, in: 5...(24 * 60), step: 5) {
                    Text("\(draft.minutes) min  ·  \(hoursText(draft.minutes)) h")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .fixedSize()
            }
        }
    }

    private var assessmentRows: some View {
        Group {
            FieldRow(label: "Purpose") {
                Picker("Purpose", selection: $draft.purpose) {
                    ForEach(Vocab.assessmentPurposes, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            FieldRow(label: "Instruments", alignment: .top) {
                FlowLayout(spacing: 6) {
                    ForEach(model.activeInstruments) { i in
                        ChipButton(title: i.name, isOn: draft.instrumentIds.contains(i.id), color: .purple) {
                            if draft.instrumentIds.contains(i.id) { draft.instrumentIds.remove(i.id) }
                            else { draft.instrumentIds.insert(i.id) }
                        }
                    }
                    Button { addingInstrument = true } label: {
                        Label("Add", systemImage: "plus").font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $addingInstrument) {
                        HStack {
                            TextField("Instrument name, e.g. WAIS-IV", text: $newInstrument)
                                .textFieldStyle(.roundedBorder).frame(width: 220)
                                .onSubmit(addInstrument)
                            Button("Add", action: addInstrument).keyboardShortcut(.defaultAction)
                        }
                        .padding(12)
                    }
                }
            }
        }
    }

    private func addInstrument() {
        let name = newInstrument
        var newId: Int?
        if model.run({ r in newId = try r.addInstrument(name) }), let id = newId {
            draft.instrumentIds.insert(id)
        }
        newInstrument = ""
        addingInstrument = false
    }
}

/// Four colourful category tabs.
struct CategoryTabs: View {
    @Binding var selection: HourCategory
    var compact = false
    @Namespace private var glass

    var body: some View {
        // Liquid Glass: each tab is a glass pill; the selected one is tinted in its
        // category colour and the tint flows between tabs inside one container.
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(HourCategory.allCases) { c in
                    let on = selection == c
                    Button { selection = c } label: {
                        HStack(spacing: 6) {
                            Image(systemName: c.icon).imageScale(.small)
                            Text(c.label).lineLimit(1).fixedSize()
                        }
                        .font(compact ? .callout.weight(on ? .semibold : .regular) : .body.weight(on ? .semibold : .regular))
                        .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 5 : 7)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .glassEffect(on ? .regular.tint(c.color).interactive() : .regular.interactive(),
                                     in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(c.color.opacity(on ? 0.9 : 0), lineWidth: 1.5))
                        .glassEffectID(c.rawValue, in: glass)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: selection)
    }
}

/// Edit an existing entry.
struct EditEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: Int
    @State private var draft = EntryDraft()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Session").font(.title2.bold())
            if loaded { EntryFormView(draft: $draft, mode: .edit) }
            HStack {
                Button("Delete", role: .destructive) {
                    if model.run({ r in try r.deleteEntry(id: id) }) { dismiss() }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if model.run({ r in try r.updateEntry(id: id, draft.input()) }) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            guard let r = model.repo, let e = try? r.entry(id) else { return }
            draft = EntryDraft(entry: e, instrumentIds: (try? r.entryInstrumentIds(id)) ?? [])
            loaded = true
        }
    }
}
