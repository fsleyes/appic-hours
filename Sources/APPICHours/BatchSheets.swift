import AppKit
import SwiftUI
import TrackerCore
import UniformTypeIdentifiers

// MARK: - Batch add clients

struct GridRowData: Identifiable, Equatable {
    let id = UUID()
    var v = Array(repeating: "", count: Batch.fields.count)
    var kind: ClientKind? = nil         // from an imported file's Type column; nil = sheet default
    var closed = false                  // add this client with their case already closed
    var closedOn: String? = nil         // closed date from an imported file; nil = the sheet's date
    var isBlank: Bool { v.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

struct BatchClientsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [GridRowData] = (0..<12).map { _ in GridRowData() }
    @State private var defaultSite: String?
    @State private var defaultKind: ClientKind = .therapy
    @State private var closedOn = Date()
    @State private var closureNote = ""

    static let choices: [String: [String]] = [
        "age_group": Vocab.clientAges, "race": Vocab.races, "gender": Vocab.genders,
        "orientation": Vocab.orientations, "disabilities": Vocab.disabilities,
    ]

    /// Validation of the non-blank rows, keyed by row id.
    private var parsed: [UUID: Batch.ParsedRow] {
        let filled = rows.filter { !$0.isBlank }
        var p = Batch.parseRows(filled.map { $0.v as [Any?] }, repo: model.repo, defaultSite: defaultSite,
                                hasHeader: false, defaultKind: defaultKind)
        for (i, row) in filled.enumerated() where row.kind != nil { p[i].values["kind"] = row.kind!.rawValue }
        return Dictionary(uniqueKeysWithValues: zip(filled.map(\.id), p))
    }

    var body: some View {
        let parsed = parsed
        let bad = parsed.values.filter { !$0.ok }.count
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Batch Add Clients").font(.title2.bold())
                    Text("Type, paste rows from Excel or Google Sheets, or import a file. Values are matched loosely — “white”, “F”, “34”, “teen”, “SMI; learning”. Your old tracker’s Clients tab imports as-is.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button { paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                Button { importFile() } label: { Label("Import CSV / Excel…", systemImage: "square.and.arrow.down") }
                Button { saveTemplate() } label: { Label("Template…", systemImage: "doc.badge.plus") }
                Menu {
                    ForEach(Array(Batch.fields.enumerated()), id: \.offset) { i, f in
                        Button(f.header) { fillDown(i) }
                    }
                } label: { Label("Fill Down", systemImage: "arrow.down.to.line") }
                .fixedSize()
                Button { rows += (0..<10).map { _ in GridRowData() } } label: { Label("10 Rows", systemImage: "plus") }
                Button(role: .destructive) { rows = (0..<12).map { _ in GridRowData() } } label: {
                    Label("Clear", systemImage: "trash")
                }
                Spacer()
            }
            .controlSize(.regular)

            HStack(spacing: 14) {
                Picker("Type", selection: $defaultKind) {
                    ForEach(ClientKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
                .help("Client type for every row (a Type column in an imported file overrides it per row)")
                Picker("Site for blank rows", selection: $defaultSite) {
                    Text("None").tag(String?.none)
                    ForEach(model.activeSites) { Text($0.name).tag(String?.some($0.name)) }
                }
                .fixedSize()
                Menu {
                    Button("Mark All as Closed") { setAllClosed(true) }
                    Button("Mark All as Open") { setAllClosed(false) }
                } label: {
                    Label("Case status", systemImage: "lock")
                }
                .fixedSize()
                .help("Clients you've already finished with can be added with their case closed — or use the lock on each row")
                if closedCount > 0 {
                    DatePicker("Closed on", selection: $closedOn, displayedComponents: .date).fixedSize()
                        .help("Used for closed rows without their own date (a date in an imported file's Closed column wins)")
                    TextField("Reason", text: $closureNote, prompt: Text("Reason (optional)"))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                }
                Spacer()
            }

            Table(rows) {
                TableColumn("#") { r in
                    HStack(spacing: 4) {
                        Button { deleteRow(r.id) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(r.isBlank ? .tertiary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete this row")
                        Text("\((rows.firstIndex(of: r) ?? 0) + 1)").foregroundStyle(.tertiary).monospacedDigit()
                        Button { toggleClosed(r.id) } label: {
                            Image(systemName: r.closed ? "lock.fill" : "lock.open")
                                .foregroundStyle(r.closed ? Color.red : Color.secondary.opacity(r.isBlank ? 0.3 : 0.6))
                        }
                        .buttonStyle(.plain)
                        .help(r.closed ? "Will be added with the case closed\(r.closedOn.map { " (\(Day.medium($0)))" } ?? "") — click to keep it open"
                                       : "Click to add this client with their case already closed")
                        if let k = r.kind {
                            Image(systemName: k.icon).font(.caption2)
                                .foregroundStyle(k == .therapy ? .blue : .purple)
                                .help("\(k.label) client (from the imported file)")
                        }
                    }
                }
                .width(84)
                col(0, 110); col(1, 170); col(2, 130); col(3, 190); col(4, 100)
                col(5, 120); col(6, 190); col(7, 110); col(8, 140)
            }
            .frame(minHeight: 360)

            HStack {
                if parsed.isEmpty {
                    Label("No rows yet", systemImage: "info.circle").foregroundStyle(.secondary)
                } else if bad > 0 {
                    Label("\(parsed.count - bad) ready · \(bad) need fixing — hover the red cells",
                          systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Label("All \(parsed.count) rows look good" + (closedCount > 0 ? " · \(closedCount) will be added as closed" : ""),
                          systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add \(parsed.count) Client\(parsed.count == 1 ? "" : "s")") { save(parsed) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(parsed.isEmpty || bad > 0)
            }
        }
        .padding(24)
        .frame(width: sheetWidth(1240), height: sheetHeight(680))
        .onAppear { if model.activeSites.count == 1 { defaultSite = model.activeSites[0].name } }
    }

    @TableColumnBuilder<GridRowData, Never>
    private func col(_ i: Int, _ width: CGFloat) -> some TableColumnContent<GridRowData, Never> {
        let f = Batch.fields[i]
        TableColumn(f.header) { r in cell(r, i) }.width(min: 70, ideal: width)
    }

    private func cell(_ r: GridRowData, _ i: Int) -> some View {
        let key = Batch.fields[i].key
        let err = parsed[r.id]?.errors[key]
        let binding = Binding<String>(
            get: { rows.first { $0.id == r.id }?.v[i] ?? "" },
            set: { new in if let idx = rows.firstIndex(where: { $0.id == r.id }) { rows[idx].v[i] = new } })
        return HStack(spacing: 2) {
            TextField("", text: binding).textFieldStyle(.plain)
            if let opts = key == "site" ? model.sites.map(\.name) : Self.choices[key] {
                Menu {
                    ForEach(opts, id: \.self) { o in
                        Button(o) {
                            if key == "disabilities" && !binding.wrappedValue.isEmpty {
                                binding.wrappedValue += "; " + o
                            } else { binding.wrappedValue = o }
                        }
                    }
                } label: { Image(systemName: "chevron.down") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(err == nil ? Color.clear : Color.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
        .help(err ?? "")
    }

    // MARK: actions

    private func firstEmptyIndex() -> Int {
        (rows.lastIndex { !$0.isBlank }).map { $0 + 1 } ?? 0
    }

    private func load(_ values: [[String]], kinds: [ClientKind?] = [], closed: [(Bool, String?)] = []) {
        var start = firstEmptyIndex()
        for (n, v) in values.enumerated() {
            if start >= rows.count { rows.append(GridRowData()) }
            var row = GridRowData()
            for (i, s) in v.prefix(Batch.fields.count).enumerated() { row.v[i] = s }
            row.kind = n < kinds.count ? kinds[n] : nil
            if n < closed.count { (row.closed, row.closedOn) = closed[n] }
            rows[start] = row
            start += 1
        }
        if rows.count < start + 3 { rows += (0..<3).map { _ in GridRowData() } }
    }

    /// Normalised values where they parsed; raw text where they didn't (so you can fix it).
    private func load(parsed: [Batch.ParsedRow]) {
        load(parsed.map { p in
            Batch.fieldNames.map { f in p.errors[f] != nil ? (p.raw[f] ?? p.values[f] ?? "") : (p.values[f] ?? "") }
        }, kinds: parsed.map { p in p.raw["kind"].flatMap(Batch.parseKind) },
           closed: parsed.map { p in (p.values["closed"] == "1", p.values["closed_on"]) })
    }

    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        let delim: Character = text.contains("\t") ? "\t" : ","
        let table = CSV.parse(text, delimiter: delim)
        if let first = table.first, Batch.looksLikeHeader(first) {
            load(parsed: Batch.parseRows(table, repo: model.repo, defaultSite: defaultSite, hasHeader: true))
        } else {
            load(table)
        }
    }

    private func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText,
                                 UTType(filenameExtension: "xlsx") ?? .data]
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let table = try Batch.readFile(url)
            let header = table.first.map { Batch.looksLikeHeader($0.map { Batch.cellText($0) }) } ?? false
            load(parsed: Batch.parseRows(table, repo: model.repo, defaultSite: defaultSite, hasHeader: header))
        } catch {
            model.alert = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    private func saveTemplate() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "clients-template.csv"
        p.allowedContentTypes = [.commaSeparatedText]
        if p.runModal() == .OK, let url = p.url {
            try? Batch.templateCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func deleteRow(_ id: UUID) {
        rows.removeAll { $0.id == id }
        if rows.isEmpty { rows = [GridRowData()] }
    }

    private func fillDown(_ col: Int) {
        var carry = ""
        let last = rows.lastIndex { !$0.isBlank } ?? -1
        for i in rows.indices where i <= last {
            if rows[i].v[col].isEmpty { rows[i].v[col] = carry } else { carry = rows[i].v[col] }
        }
    }

    private var closedCount: Int { rows.filter { $0.closed && !$0.isBlank }.count }

    private func toggleClosed(_ id: UUID) {
        if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].closed.toggle() }
    }

    private func setAllClosed(_ on: Bool) {
        for i in rows.indices where !rows[i].isBlank { rows[i].closed = on }
    }

    private func save(_ parsed: [UUID: Batch.ParsedRow]) {
        let filled = rows.filter { parsed[$0.id] != nil }
        let ordered = filled.compactMap { parsed[$0.id] }
        let sheetDate = Day.iso(closedOn), note = closureNote
        var n = 0, nClosed = 0
        let ok = model.run { r in
            try r.db.transaction {
                let inputs = try Batch.toClientInputs(r, ordered)
                let ids = try r.addClientsBulk(inputs)
                for (row, id) in zip(filled, ids) where row.closed {
                    try r.closeClient(id: id, closedOn: row.closedOn ?? sheetDate, note: note)
                    nClosed += 1
                }
                n = ids.count
            }
        }
        if ok {
            model.showToast("Added \(n) client\(n == 1 ? "" : "s")" + (nClosed > 0 ? " (\(nClosed) closed)" : ""))
            dismiss()
        }
    }
}

extension Batch {
    static func cellText(_ v: Any?) -> String {
        switch v {
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
        case let s as String: return s
        default: return ""
        }
    }
}

// MARK: - Batch add sessions

struct SessionRowData: Identifiable, Equatable {
    let id = UUID()
    var date: Date
    var minutes: Int?        // nil = use the default duration
    var note = ""
}

struct BatchSessionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let preset: Who?
    var supervisorId: Int? = nil

    @State private var draft = EntryDraft()
    @State private var rows: [SessionRowData] = []
    @State private var showSeries = false
    @State private var seriesStart = Date()
    @State private var seriesCount = 10
    @State private var seriesEvery = 7
    @State private var showPaste = false
    @State private var pasteText = ""
    @State private var pasteBad: [String] = []

    private var logged: Set<String> {
        _ = model.revision
        guard let w = draft.who else { return [] }
        return ((try? model.repo?.loggedDates(clientId: w.clientId, groupId: w.groupId)) ?? nil) ?? []
    }

    var body: some View {
        let logged = logged
        let isos = rows.map { Day.iso($0.date) }
        let totalMin = rows.reduce(0) { $0 + ($1.minutes ?? draft.minutes) }
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Batch Add Sessions").font(.title2.bold())
                Text("Set what's the same once, then list the dates. Everything is saved together — or not at all.")
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(title: "Every session", icon: "square.stack.3d.up")
                    ScrollView { EntryFormView(draft: $draft, mode: .batchTemplate).padding(.trailing, 6) }
                }
                .card()
                .frame(width: min(520, sheetWidth(1080) * 0.48))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CardTitle(title: "Dates", icon: "calendar")
                        Pill(text: "\(rows.count)", color: draft.category.color)
                    }
                    HStack(spacing: 8) {
                        Button { addOne() } label: { Label("Add Date", systemImage: "plus") }
                        Button {
                            // default: a series that ends today
                            seriesStart = Day.date(Day.add(Day.today(), days: -seriesEvery * (seriesCount - 1))) ?? Date()
                            showSeries = true
                        } label: { Label("Weekly Series…", systemImage: "repeat") }
                            .popover(isPresented: $showSeries, arrowEdge: .bottom) { seriesPopover }
                        Button { showPaste = true } label: { Label("Paste Dates…", systemImage: "doc.on.clipboard") }
                            .popover(isPresented: $showPaste, arrowEdge: .bottom) { pastePopover }
                        Spacer()
                        Menu {
                            Button("Sort by Date") { rows.sort { $0.date < $1.date } }
                            Button("Remove Duplicates") { dedupe() }
                            Divider()
                            Button("Clear All", role: .destructive) { rows = [] }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                    List {
                        ForEach($rows) { $row in
                            dateRow($row, isos: isos, logged: logged)
                        }
                        .onDelete { rows.remove(atOffsets: $0) }
                    }
                    .listStyle(.inset)
                    .overlay {
                        if rows.isEmpty {
                            ContentUnavailableView {
                                Label("No dates yet", systemImage: "calendar.badge.plus")
                            } description: {
                                Text("Add dates one by one, generate a weekly series, or paste a list like\n9/2, 9/9, 9/16")
                            }
                        }
                    }
                }
                .card()
            }
            HStack {
                if !rows.isEmpty {
                    Text("\(rows.count) session\(rows.count == 1 ? "" : "s") · \(hoursText(totalMin)) h · \(model.label(draft.usesWho ? draft.who : nil))" + (isos.filter { $0 > Day.today() }.isEmpty ? "" : " · \(isos.filter { $0 > Day.today() }.count) planned (future dates)"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add \(rows.count) Session\(rows.count == 1 ? "" : "s")") { save() }
                    .buttonStyle(.borderedProminent).tint(draft.category.color)
                    .keyboardShortcut(.defaultAction).disabled(rows.isEmpty)
            }
        }
        .padding(24)
        .frame(width: sheetWidth(1080), height: sheetHeight(720))
        .onAppear {
            draft = model.logDraft
            draft.who = preset
            draft.note = ""
            if preset != nil { model.applyWhoDefaults(&draft) }
            if let sid = supervisorId {
                draft.category = .supervision
                draft.who = nil
                draft.supervisorId = sid
                model.applySupervisorDefaults(&draft)
            }
            if draft.siteId == nil { draft.siteId = model.activeSites.first?.id }
        }
    }

    private func dateRow(_ row: Binding<SessionRowData>, isos: [String], logged: Set<String>) -> some View {
        let iso = Day.iso(row.wrappedValue.date)
        let dupInList = isos.filter { $0 == iso }.count > 1
        let already = logged.contains(iso)
        let future = iso > Day.today()
        let warn = dupInList ? "This date is listed twice." :
            already ? "\(model.label(draft.who)) already has a session on this date." : nil
        return HStack(spacing: 10) {
            Text("\((rows.firstIndex(of: row.wrappedValue) ?? 0) + 1)").foregroundStyle(.tertiary).monospacedDigit()
                .frame(width: 22, alignment: .trailing)
            DatePicker("Date", selection: row.date, displayedComponents: .date).labelsHidden().fixedSize()
            Text(Day.short(iso).prefix(3)).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
            Stepper(value: Binding(get: { row.wrappedValue.minutes ?? draft.minutes },
                                   set: { row.wrappedValue.minutes = $0 }), in: 5...(24 * 60), step: 5) {
                Text("\(row.wrappedValue.minutes ?? draft.minutes) min").monospacedDigit()
                    .foregroundStyle(row.wrappedValue.minutes == nil ? .secondary : .primary)
            }
            .fixedSize()
            TextField("Note", text: row.note, prompt: Text("Note (optional)")).textFieldStyle(.roundedBorder)
            if let warn {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(warn)
            }
            if future {
                Image(systemName: "clock").foregroundStyle(.blue)
                    .help("Future date — saved as planned. It won't count until you confirm it on or after this date.")
            }
            Button { rows.removeAll { $0.id == row.wrappedValue.id } } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var seriesPopover: some View {
        Form {
            DatePicker("First session", selection: $seriesStart, displayedComponents: .date)
            Stepper("\(seriesCount) sessions", value: $seriesCount, in: 1...60)
            Picker("Every", selection: $seriesEvery) {
                Text("Week").tag(7)
                Text("2 weeks").tag(14)
                Text("Day").tag(1)
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                Button("Add \(seriesCount) Dates") {
                    for iso in Batch.repeatingDates(start: Day.iso(seriesStart), count: seriesCount, everyDays: seriesEvery) {
                        if let d = Day.date(iso) { rows.append(SessionRowData(date: d)) }
                    }
                    showSeries = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
    }

    private var pastePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One date per line, or separated by commas. Formats like 9/2/2026, 2026-09-02, Sep 2, 2026 — or 9/2 for this year.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $pasteText).font(.body.monospaced()).frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            if !pasteBad.isEmpty {
                Text("Couldn't read: \(pasteBad.joined(separator: ", "))").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Paste Clipboard") { pasteText = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer()
                Button("Add Dates") {
                    let (dates, bad) = Batch.parseDateList(pasteText)
                    rows += dates.compactMap { Day.date($0).map { SessionRowData(date: $0) } }
                    pasteBad = bad
                    if bad.isEmpty { pasteText = ""; showPaste = false }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    /// Next week after the last date — or, once that would be in the future, the week
    /// before the earliest (catching up on past sessions is the usual case).
    private func addOne() {
        let today = Day.today()
        var next = today
        if let last = rows.last {
            next = Day.add(Day.iso(last.date), days: 7)
            if next > today, let earliest = rows.map({ Day.iso($0.date) }).min() {
                next = Day.add(earliest, days: -7)
            }
        }
        rows.append(SessionRowData(date: Day.date(next) ?? Date()))
    }

    private func dedupe() {
        var seen = Set<String>()
        rows = rows.filter { seen.insert(Day.iso($0.date)).inserted }
    }

    private func save() {
        let inputs = rows.map { r in
            draft.input(date: Day.iso(r.date), minutes: r.minutes ?? draft.minutes, note: r.note.isEmpty ? "" : r.note)
        }.map { i -> EntryInput in var i = i; if i.note == "" { i.note = nil }; return i }
        var ids: [Int] = []
        if model.run({ r in ids = try r.addEntriesBulk(inputs) }) {
            let who = draft.usesWho && draft.who != nil ? " for \(model.label(draft.who))" : ""
            model.showToast("Added \(ids.count) session\(ids.count == 1 ? "" : "s")\(who)", undo: ids)
            dismiss()
        }
    }
}

/// Sheets can't be larger than their window — size them to fit (window minus a margin).
/// Uses the app's main document window (not the key window, which is nil in the background).
@MainActor private func hostWindowFrame() -> NSRect? {
    NSApp.windows
        .filter { $0.isVisible && $0.sheetParent == nil && !($0 is NSPanel) && $0.styleMask.contains(.titled) }
        .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?
        .frame
}

@MainActor func sheetWidth(_ ideal: CGFloat) -> CGFloat {
    guard let w = hostWindowFrame()?.width else { return ideal }
    return max(760, min(ideal, w - 60))
}

@MainActor func sheetHeight(_ ideal: CGFloat) -> CGFloat {
    guard let h = hostWindowFrame()?.height else { return ideal }
    return max(520, min(ideal, h - 80))
}
