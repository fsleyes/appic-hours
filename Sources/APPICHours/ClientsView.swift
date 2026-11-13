import SwiftUI
import TrackerCore

enum StatusFilter: String, CaseIterable, Identifiable {
    case open = "Open", closed = "Closed", all = "All"
    var id: String { rawValue }
    func keep(_ closed: Bool) -> Bool {
        switch self { case .open: return !closed; case .closed: return closed; case .all: return true }
    }
}

struct ClientsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter: StatusFilter = .open
    @State private var newGroup = false
    /// Site folders under Assessment clients that are collapsed (site names, one per line).
    @AppStorage("clientsCollapsedAssessmentSites") private var collapsedSites = ""

    private var clients: [Client] {
        model.clients.filter { filter.keep($0.isClosed) && matches($0.code, $0.siteName) }
    }
    private var groups: [ClientGroup] {
        model.groups.filter { filter.keep($0.isClosed) && matches($0.name, $0.siteName) }
    }
    private func matches(_ a: String, _ b: String) -> Bool {
        search.isEmpty || a.localizedCaseInsensitiveContains(search) || b.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("Status", selection: $filter) {
                    ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .padding(12)
                List {
                    ForEach(ClientKind.allCases) { kind in
                        let list = clients.filter { $0.kind == kind }
                        if !list.isEmpty {
                            Section {
                                if kind == .assessment {
                                    ForEach(siteFolders(list), id: \.name) { folder in
                                        DisclosureGroup(isExpanded: expanded(folder.name)) {
                                            ForEach(folder.clients, id: \.rowKey) { c in clientRow(c, showSite: false) }
                                        } label: {
                                            Label("\(folder.name) · \(folder.clients.count)", systemImage: "folder")
                                                .font(.callout.weight(.medium))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } else {
                                    ForEach(list, id: \.rowKey) { c in clientRow(c) }
                                }
                            } header: {
                                Label("\(kind == .therapy ? "Therapy clients" : "Assessment clients") · \(list.count)",
                                      systemImage: kind.icon)
                            }
                        }
                    }
                    if !groups.isEmpty {
                        Section("Groups, families & couples · \(groups.count)") {
                            ForEach(groups, id: \.rowKey) { g in
                                selectable(.group(g.id)) {
                                    ClientRow(name: g.name, subtitle: "\(g.shortType.capitalized) · \(g.nSessions) sessions · \(hoursText(g.minutes)) h" + (g.nPlanned > 0 ? " · \(g.nPlanned) planned" : ""),
                                              closed: g.isClosed, isGroup: true)
                                }
                                    .contextMenu {
                                        Button("Edit…") { model.editWho = WhoRef(who: .group(g.id)) }
                                        Button("Add Sessions…") { model.batchSessions = WhoRef(who: .group(g.id)) }
                                        Divider()
                                        Button("Delete…", role: .destructive) { model.pendingDelete = .group(g.id) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if clients.isEmpty && groups.isEmpty {
                        if model.clients.isEmpty && model.groups.isEmpty {
                            ContentUnavailableView {
                                Label("No clients yet", systemImage: "person.crop.circle.badge.plus")
                            } description: {
                                Text("Add clients one at a time, or paste a whole list at once.")
                            } actions: {
                                Button("Add Client") { model.showNewClient = true }.buttonStyle(.borderedProminent)
                                Button("Batch Add Clients…") { model.showBatchClients = true }
                            }
                        } else {
                            ContentUnavailableView.search(text: search)
                        }
                    }
                }
            }
            .frame(width: 330)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            Group {
                if let who = model.clientSelection, exists(who) {
                    ClientDetailView(who: who).id(who)
                } else {
                    EmptyHint(title: "No client selected", icon: "person.crop.circle",
                              message: "Pick a client or group to see their sessions, details and reports.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Clients")
        .searchable(text: $search, placement: .toolbar, prompt: "Search clients")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("New Client…") { model.showNewClient = true }
                    Button("New Group, Family or Couple…") { newGroup = true }
                    Divider()
                    Button("Batch Add Clients…") { model.showBatchClients = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(model.sites.isEmpty)
                .help(model.sites.isEmpty ? "Add a site in Setup first" : "Add clients")
            }
        }
        .sheet(isPresented: $model.showNewClient) { ClientEditorSheet(client: nil) }
        .sheet(isPresented: $newGroup) { GroupEditorSheet(group: nil) }
        .sheet(item: $model.editWho) { ref in
            switch ref.who {
            case .client(let id): if let c = model.client(id) { ClientEditorSheet(client: c) }
            case .group(let id): if let g = model.group(id) { GroupEditorSheet(group: g) }
            case nil: EmptyView()
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { model.pendingDelete != nil },
                                                             set: { if !$0 { model.pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: model.pendingDelete) { who in
            Button("Delete Permanently", role: .destructive) {
                let name = model.label(who)
                model.run { r in
                    if let id = who.clientId { try r.deleteClient(id: id) }
                    if let id = who.groupId { try r.deleteGroup(id: id) }
                }
                if model.clientSelection == who { model.clientSelection = nil }
                model.showToast("Deleted \(name)")
            }
            if !model.isClosed(who) {
                Button("Close Case Instead") {
                    model.run { r in
                        if let id = who.clientId { try r.closeClient(id: id) }
                        if let id = who.groupId { try r.closeGroup(id: id) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { who in
            Text(deleteMessage(who))
        }
    }

    private var deleteName: String { model.label(model.pendingDelete) }
    private var deleteTitle: String { "Delete \(deleteName)?" }

    private func deleteMessage(_ who: Who) -> String {
        let i = (try? model.repo?.deletionImpact(clientId: who.clientId, groupId: who.groupId)) ?? nil
        var parts = ["This permanently removes \(i?.sessions ?? 0) session\((i?.sessions ?? 0) == 1 ? "" : "s") (\(hoursText(i?.minutes ?? 0)) h)"]
        if let r = i?.reports, r > 0 { parts.append("\(r) report\(r == 1 ? "" : "s")") }
        return parts.joined(separator: " and ")
            + ", plus any recurring sessions. Those hours will no longer count toward your AAPI totals. This can't be undone (daily backups are kept in your data folder).\n\nTo keep the hours, close the case instead."
    }

    /// Clients split into one folder per site, in the order sites were set up.
    private func siteFolders(_ list: [Client]) -> [(name: String, clients: [Client])] {
        let bySite = Dictionary(grouping: list, by: \.siteName)
        let order = model.sites.map(\.name)
        return bySite.keys.sorted {
            (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1)
        }.map { ($0, bySite[$0] ?? []) }
    }

    /// Folders stay open while searching so matches are never hidden.
    private func expanded(_ site: String) -> Binding<Bool> {
        Binding(
            get: { !search.isEmpty || !collapsedSites.split(separator: "\n").contains(Substring(site)) },
            set: { open in
                var set = Set(collapsedSites.split(separator: "\n").map(String.init))
                if open { set.remove(site) } else { set.insert(site) }
                collapsedSites = set.sorted().joined(separator: "\n")
            })
    }

    private func clientRow(_ c: Client, showSite: Bool = true) -> some View {
        selectable(.client(c.id)) {
            ClientRow(name: c.code, subtitle: (showSite ? "\(c.siteName) · " : "") + "\(c.nSessions) sessions · \(hoursText(c.minutes)) h" + (c.nPlanned > 0 ? " · \(c.nPlanned) planned" : ""),
                      closed: c.isClosed, isGroup: false)
        }
        .contextMenu {
            Button("Edit Client…") { model.editWho = WhoRef(who: .client(c.id)) }
            Button("Add Sessions…") { model.batchSessions = WhoRef(who: .client(c.id)) }
            Divider()
            Button("Delete Client…", role: .destructive) { model.pendingDelete = .client(c.id) }
        }
    }

    /// A list row that selects on click. (List(selection:) didn't register real clicks here.)
    private func selectable<Content: View>(_ who: Who, @ViewBuilder _ content: () -> Content) -> some View {
        let selected = model.clientSelection == who
        return Button { model.clientSelection = who } label: {
            content()
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.accentColor.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func exists(_ w: Who) -> Bool {
        switch w {
        case .client(let id): return model.client(id) != nil
        case .group(let id): return model.group(id) != nil
        }
    }
}

struct ClientRow: View {
    var name: String
    var subtitle: String
    var closed: Bool
    var isGroup: Bool
    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: name, size: 30, isGroup: isGroup).opacity(closed ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if closed { Pill(text: "Closed", color: .secondary) }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Detail

struct ClientDetailView: View {
    enum Tab: String, CaseIterable { case sessions = "Sessions", details = "Details", reports = "Reports" }

    @Environment(AppModel.self) private var model
    let who: Who
    @State private var tab: Tab = .sessions
    @State private var selection = Set<Int>()
    @State private var closing = false
    @State private var addingReport = false

    private var entries: [Entry] {
        _ = model.revision
        return ((try? model.repo?.entries(clientId: who.clientId, groupId: who.groupId)) ?? nil) ?? []
    }
    private var client: Client? { model.client(who.clientId) }
    private var group: ClientGroup? { model.group(who.groupId) }
    private var name: String { client?.code ?? group?.name ?? "" }
    private var closedOn: String? { client?.closedOn ?? group?.closedOn }
    private var closureNote: String? { client?.closureNote ?? group?.closureNote }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases.filter { $0 != .reports || client != nil }, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            switch tab {
            case .sessions:
                EntryTable(entries: entries, selection: $selection, showWho: false)
            case .details:
                ScrollView {
                    if let c = client { ClientDetailsForm(client: c) }
                    if let g = group { GroupDetailsForm(group: g) }
                }
            case .reports:
                if let c = client { ReportsTab(client: c, adding: $addingReport) }
            }
        }
        .padding(24)
        .sheet(isPresented: $closing) { CloseCaseSheet(who: who, name: name) }
        .sheet(isPresented: $addingReport) { if let c = client { ReportSheet(client: c) } }
    }

    private func actionRow(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { model.startLog(for: who) } label: {
                Label(compact ? "Log" : "Log Session", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .disabled(closedOn != nil)
            .help("Log a session for \(name)")
            Button { model.batchSessions = WhoRef(who: who) } label: {
                Label("Add Sessions…", systemImage: "calendar.badge.plus")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .help("Add several sessions at once")
            Button { model.editWho = WhoRef(who: who) } label: {
                Label(client != nil ? "Edit Client…" : "Edit Details…", systemImage: "pencil")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .help(client != nil ? "Edit this client's ID, site, age and demographics" : "Edit this group's details")
            Spacer(minLength: 8)
            if closedOn != nil {
                Button(compact ? "Reopen" : "Reopen Case") {
                    model.run { r in
                        if let id = who.clientId { try r.reopenClient(id: id) }
                        if let id = who.groupId { try r.reopenGroup(id: id) }
                    }
                }
            } else {
                Button(compact ? "Close…" : "Close Case…") { closing = true }
                    .help("Close this case")
            }
            Menu {
                Button(client != nil ? "Delete Client…" : "Delete…", role: .destructive) {
                    model.pendingDelete = who
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("More")
        }
        .fixedSize(horizontal: !compact, vertical: false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Avatar(name: name, size: 60, isGroup: group != nil).opacity(closedOn == nil ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(name).font(.system(size: 26, weight: .bold, design: .rounded))
                        if let closedOn {
                            Pill(text: "Closed \(Day.medium(closedOn))", color: .red, icon: "lock.fill")
                        } else {
                            Pill(text: "Open", color: .green, icon: "circle.fill")
                        }
                    }
                    FlowLayout(spacing: 6) {
                        if let c = client {
                            Pill(text: c.kind.label, color: c.kind == .therapy ? .blue : .purple, icon: c.kind.icon)
                            Pill(text: c.siteName, icon: "building.2")
                            Pill(text: c.ageGroup)
                            if let g = c.gender { Pill(text: g) }
                            if let r = c.race { Pill(text: r) }
                            if let o = c.orientation { Pill(text: o) }
                            ForEach(c.disabilities, id: \.self) { Pill(text: $0, color: .indigo) }
                        }
                        if let g = group {
                            Pill(text: g.siteName, icon: "building.2")
                            Pill(text: g.groupType)
                            if let a = g.ageGroup { Pill(text: a) }
                        }
                    }
                    let counted = entries.filter { !$0.planned }
                    let nPlanned = entries.count - counted.count
                    let mins = counted.reduce(0) { $0 + $1.minutes }
                    Text("\(counted.count) sessions · \(hoursText(mins)) h"
                         + (nPlanned > 0 ? " · \(nPlanned) planned" : "")
                         + (counted.first.map { " · last seen \(Day.medium($0.date))" } ?? "")
                         + (closureNote.map { " · closed: \($0)" } ?? ""))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            // Actions get their own row; on narrow windows they switch to compact labels.
            ViewThatFits(in: .horizontal) {
                actionRow(compact: false)
                actionRow(compact: true)
            }
        }
    }
}

// MARK: - Details forms

struct ClientDraft: Equatable {
    var code = ""
    var siteId: Int?
    var ageGroup = "18-64 years old"
    var race: String?
    var gender: String?
    var orientation: String?
    var disabilities: Set<String> = []
    var hasOpened = false
    var openedOn = Date()
    var notes = ""
    var kind: ClientKind = .therapy

    init() {}
    init(_ c: Client) {
        kind = c.designatedKind
        code = c.code; siteId = c.siteId; ageGroup = c.ageGroup; race = c.race; gender = c.gender
        orientation = c.orientation; disabilities = Set(c.disabilities)
        hasOpened = c.openedOn != nil; openedOn = c.openedOn.flatMap(Day.date) ?? Date()
        notes = c.notes ?? ""
    }
    var input: ClientInput {
        ClientInput(code: code, siteId: siteId, ageGroup: ageGroup, race: race, gender: gender,
                    orientation: orientation, disabilities: Vocab.disabilities.filter(disabilities.contains),
                    notes: notes.isEmpty ? nil : notes, openedOn: hasOpened ? Day.iso(openedOn) : nil,
                    kind: kind)
    }
}

struct ClientFields: View {
    @Environment(AppModel.self) private var model
    @Binding var d: ClientDraft
    var body: some View {
        Section {
            Picker("Client type", selection: $d.kind) {
                ForEach(ClientKind.allCases) { k in Label(k.label, systemImage: k.icon).tag(k) }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Once they have sessions this follows the sessions: any therapy session makes them a therapy client; only assessment sessions makes them an assessment client.")
        }
        Section {
            TextField("Client ID", text: $d.code, prompt: Text("Pseudonym, initials or ID — never a full name"))
            Picker("Site", selection: $d.siteId) {
                if d.siteId == nil { Text("Choose…").tag(Int?.none) }
                ForEach(model.sites) { Text($0.name).tag(Int?.some($0.id)) }
            }
            Picker("Age group", selection: $d.ageGroup) {
                ForEach(Vocab.clientAges, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Record case-opened date", isOn: $d.hasOpened)
            if d.hasOpened { DatePicker("Opened", selection: $d.openedOn, displayedComponents: .date) }
        }
        Section("Demographics") {
            optionalPicker("Race / ethnicity", $d.race, Vocab.races)
            optionalPicker("Gender", $d.gender, Vocab.genders)
            optionalPicker("Sexual orientation", $d.orientation, Vocab.orientations)
            LabeledContent("Disabilities") {
                FlowLayout(spacing: 6) {
                    ForEach(Vocab.disabilities, id: \.self) { x in
                        ChipButton(title: x, isOn: d.disabilities.contains(x), color: .indigo) {
                            if d.disabilities.contains(x) { d.disabilities.remove(x) } else { d.disabilities.insert(x) }
                        }
                    }
                }
                .frame(maxWidth: 380, alignment: .trailing)
            }
        }
        Section("Notes") {
            TextField("Notes", text: $d.notes, prompt: Text("Optional — no identifying details"), axis: .vertical)
                .lineLimit(2...4).labelsHidden()
        }
    }

    private func optionalPicker(_ label: String, _ b: Binding<String?>, _ values: [String]) -> some View {
        Picker(label, selection: b) {
            Text("Not recorded").tag(String?.none)
            ForEach(values, id: \.self) { Text($0).tag(String?.some($0)) }
        }
    }
}

struct ClientDetailsForm: View {
    @Environment(AppModel.self) private var model
    let client: Client
    @State private var d: ClientDraft

    init(client: Client) {
        self.client = client
        _d = State(initialValue: ClientDraft(client))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Form { ClientFields(d: $d) }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(minHeight: 520)
            HStack {
                Button("Revert") { d = ClientDraft(client) }.disabled(d.input == ClientDraft(client).input)
                Button("Save Changes") { model.run { r in try r.updateClient(id: client.id, d.input) } }
                    .buttonStyle(.borderedProminent).disabled(d.input == ClientDraft(client).input)
            }
        }
    }
}

struct GroupDraft: Equatable {
    var name = ""
    var groupType = "Group Therapy"
    var siteId: Int?
    var ageGroup: String?
    var notes = ""
    init() {}
    init(_ g: ClientGroup) {
        name = g.name; groupType = g.groupType; siteId = g.siteId; ageGroup = g.ageGroup; notes = g.notes ?? ""
    }
}

struct GroupFields: View {
    @Environment(AppModel.self) private var model
    @Binding var d: GroupDraft
    var body: some View {
        Section {
            TextField("Name", text: $d.name, prompt: Text("e.g. DBT Skills Group (co-lead), Family R"))
            Picker("Type", selection: $d.groupType) {
                ForEach(Vocab.groupTypes, id: \.self) { Text($0).tag($0) }
            }
            Picker("Site", selection: $d.siteId) {
                if d.siteId == nil { Text("Choose…").tag(Int?.none) }
                ForEach(model.sites) { Text($0.name).tag(Int?.some($0.id)) }
            }
            Picker("Member ages", selection: $d.ageGroup) {
                Text("Not applicable").tag(String?.none)
                ForEach(Vocab.groupAges, id: \.self) { Text($0).tag(String?.some($0)) }
            }
        }
        Section("Notes") {
            TextField("Notes", text: $d.notes, prompt: Text("Optional"), axis: .vertical).lineLimit(2...4).labelsHidden()
        }
    }
}

struct GroupDetailsForm: View {
    @Environment(AppModel.self) private var model
    let group: ClientGroup
    @State private var d: GroupDraft
    init(group: ClientGroup) {
        self.group = group
        _d = State(initialValue: GroupDraft(group))
    }
    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Form { GroupFields(d: $d) }.formStyle(.grouped).scrollDisabled(true).frame(minHeight: 300)
            HStack {
                Button("Revert") { d = GroupDraft(group) }.disabled(d == GroupDraft(group))
                Button("Save Changes") {
                    model.run { r in
                        try r.updateGroup(id: group.id, name: d.name, groupType: d.groupType, siteId: d.siteId,
                                          ageGroup: d.ageGroup, notes: d.notes)
                    }
                }
                .buttonStyle(.borderedProminent).disabled(d == GroupDraft(group))
            }
        }
    }
}

// MARK: - Sheets

struct SheetScaffold<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var confirm: String
    var confirmDisabled = false
    var destructive = false
    var width: CGFloat = 560
    var onConfirm: () -> Bool
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
            }
            .padding([.horizontal, .top], 24)
            content
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirm) { if onConfirm() { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(destructive ? .red : .accentColor)
                    .disabled(confirmDisabled)
            }
            .padding(20)
        }
        .frame(width: width)
    }
}

struct ClientEditorSheet: View {
    @Environment(AppModel.self) private var model
    let client: Client?
    @State private var d = ClientDraft()
    @State private var alreadyClosed = false
    @State private var closedOn = Date()
    @State private var closureNote = ""
    var body: some View {
        SheetScaffold(title: client.map { "Edit \($0.code)" } ?? "New Client",
                      subtitle: "Use a pseudonym or ID only.",
                      confirm: client == nil ? "Add Client" : "Save Changes",
                      confirmDisabled: d.code.trimmingCharacters(in: .whitespaces).isEmpty) {
            if let client {
                return model.run { r in try r.updateClient(id: client.id, d.input) }
            }
            var newId: Int?
            let ok = model.run { r in
                try r.db.transaction {
                    let id = try r.addClient(d.input)
                    if alreadyClosed {
                        try r.closeClient(id: id, closedOn: Day.iso(closedOn), note: closureNote)
                    }
                    newId = id
                }
            }
            if ok, let id = newId { model.clientSelection = .client(id) }
            return ok
        } content: {
            Form {
                ClientFields(d: $d)
                if client == nil {
                    Section {
                        Toggle("Case already closed", isOn: $alreadyClosed)
                        if alreadyClosed {
                            DatePicker("Closed on", selection: $closedOn, displayedComponents: .date)
                            TextField("Reason", text: $closureNote, prompt: Text("Optional — e.g. goals met, transferred"))
                        }
                    } header: {
                        Text("Case status")
                    } footer: {
                        Text("For a client you've already finished with: their sessions still count, but they won't appear in quick-log.")
                    }
                }
            }
            .formStyle(.grouped).frame(height: client == nil ? 620 : 560)
        }
        .onAppear {
            if let client { d = ClientDraft(client) }
            if d.siteId == nil { d.siteId = model.activeSites.first?.id }
        }
    }
}

struct GroupEditorSheet: View {
    @Environment(AppModel.self) private var model
    let group: ClientGroup?
    @State private var d = GroupDraft()
    var body: some View {
        SheetScaffold(title: group.map { "Edit \($0.name)" } ?? "New Group, Family or Couple",
                      confirm: group == nil ? "Add" : "Save Changes",
                      confirmDisabled: d.name.trimmingCharacters(in: .whitespaces).isEmpty) {
            if let group {
                return model.run { r in
                    try r.updateGroup(id: group.id, name: d.name, groupType: d.groupType, siteId: d.siteId,
                                      ageGroup: d.ageGroup, notes: d.notes)
                }
            }
            var newId: Int?
            let ok = model.run { r in
                newId = try r.addGroup(name: d.name, groupType: d.groupType, siteId: d.siteId,
                                       ageGroup: d.ageGroup, notes: d.notes)
            }
            if ok, let id = newId { model.clientSelection = .group(id) }
            return ok
        } content: {
            Form { GroupFields(d: $d) }.formStyle(.grouped).frame(height: 330)
        }
        .onAppear {
            if let group { d = GroupDraft(group) }
            if d.siteId == nil { d.siteId = model.activeSites.first?.id }
        }
    }
}

struct CloseCaseSheet: View {
    @Environment(AppModel.self) private var model
    let who: Who
    let name: String
    @State private var date = Date()
    @State private var reason = ""
    var body: some View {
        let last = (try? model.repo?.lastEntry(clientId: who.clientId, groupId: who.groupId)) ?? nil
        SheetScaffold(title: "Close \(name)'s case", subtitle: last.map { "Last session \(Day.medium($0.date))." },
                      confirm: "Close Case", destructive: true) {
            model.run { r in
                if let id = who.clientId { try r.closeClient(id: id, closedOn: Day.iso(date), note: reason) }
                if let id = who.groupId { try r.closeGroup(id: id, closedOn: Day.iso(date), note: reason) }
            }
        } content: {
            Form {
                DatePicker("Closed on", selection: $date, displayedComponents: .date)
                TextField("Reason", text: $reason, prompt: Text("Optional — e.g. goals met, transferred, dropped out"))
                Section {
                    Label("They'll leave the quick-log list and their recurring sessions stop. Their hours still count, and you can reopen any time.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }
            .formStyle(.grouped).frame(height: 230)
        }
    }
}

struct ReportsTab: View {
    @Environment(AppModel.self) private var model
    let client: Client
    @Binding var adding: Bool
    @State private var selection = Set<Int>()
    @State private var editing: Report?
    var body: some View {
        let reports = ((try? model.repo?.reports(clientId: client.id)) ?? nil) ?? []
        let _ = model.revision
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Integrated report = history + interview + at least two tests (APPIC definition).")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { adding = true } label: { Label("Report Written…", systemImage: "plus") }
            }
            if let id = selection.first, selection.count == 1, let rep = reports.first(where: { $0.id == id }) {
                HStack {
                    Spacer()
                    Button { editing = rep } label: { Label("Edit Report…", systemImage: "pencil") }
                }
            }
            Table(reports, selection: $selection) {
                TableColumn("Date") { Text(Day.medium($0.date)) }.width(110)
                TableColumn("Type") { r in
                    Pill(text: r.reportType, color: r.reportType == Vocab.integratedReport ? .purple : .secondary)
                }
                .width(150)
                TableColumn("Purpose") { Text($0.purpose) }.width(80)
                TableColumn("Instruments") { Text($0.instruments ?? "").foregroundStyle(.secondary) }
                TableColumn("Note") { Text($0.note ?? "").foregroundStyle(.secondary) }
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                if ids.count == 1, let id = ids.first, let rep = reports.first(where: { $0.id == id }) {
                    Button("Edit Report…") { editing = rep }
                    Divider()
                }
                Button(ids.count == 1 ? "Delete Report" : "Delete \(ids.count) Reports", role: .destructive) {
                    model.run { r in for id in ids { try r.deleteReport(id: id) } }
                }
            } primaryAction: { ids in
                if let id = ids.first { editing = reports.first { $0.id == id } }
            }
            .sheet(item: $editing) { rep in ReportSheet(client: client, report: rep) }
            .overlay {
                if reports.isEmpty {
                    EmptyHint(title: "No reports", icon: "doc.text", message: "Record each assessment report once it's written.")
                }
            }
        }
    }
}

struct ReportSheet: View {
    @Environment(AppModel.self) private var model
    let client: Client
    var report: Report? = nil            // set = editing an existing report
    @State private var date = Date()
    @State private var type = Vocab.integratedReport
    @State private var purpose = "Clinical"
    @State private var instruments: Set<Int> = []
    @State private var note = ""
    var body: some View {
        SheetScaffold(title: report == nil ? "Report Written" : "Edit Report", subtitle: "Client \(client.code)",
                      confirm: report == nil ? "Add Report" : "Save Changes") {
            model.run { r in
                if let report {
                    try r.updateReport(id: report.id, date: Day.iso(date), reportType: type, purpose: purpose,
                                       note: note, instrumentIds: Array(instruments))
                } else {
                    try r.addReport(clientId: client.id, date: Day.iso(date), reportType: type, purpose: purpose,
                                    note: note, instrumentIds: Array(instruments))
                }
            }
        } content: {
            Form {
                DatePicker("Date written", selection: $date, displayedComponents: .date)
                Picker("Type", selection: $type) {
                    ForEach(Vocab.reportTypes.reversed(), id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Purpose", selection: $purpose) {
                    ForEach(Vocab.assessmentPurposes, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Instruments") {
                    FlowLayout(spacing: 6) {
                        ForEach(model.activeInstruments) { i in
                            ChipButton(title: i.name, isOn: instruments.contains(i.id), color: .purple) {
                                if instruments.contains(i.id) { instruments.remove(i.id) } else { instruments.insert(i.id) }
                            }
                        }
                    }
                    .frame(maxWidth: 320, alignment: .trailing)
                }
                TextField("Note", text: $note, prompt: Text("Optional"))
            }
            .formStyle(.grouped).frame(height: 300)
        }
        .onAppear {
            if let report {
                date = Day.date(report.date) ?? Date()
                type = report.reportType
                purpose = report.purpose
                note = report.note ?? ""
                instruments = Set(((try? model.repo?.reportInstrumentIds(report.id)) ?? nil) ?? [])
                return
            }
            instruments = Set(((try? model.repo?.instrumentsUsed(clientId: client.id)) ?? nil) ?? [])
            if let p = (try? model.repo?.lastEntry(clientId: client.id))??.purpose { purpose = p }
        }
    }
}
