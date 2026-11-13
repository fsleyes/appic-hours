import SwiftUI
import TrackerCore

/// Supervision, organised by supervisor.
struct SupervisorsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedId: Int?
    @State private var search = ""
    @State private var adding = false

    private func matches(_ s: Supervisor) -> Bool {
        search.isEmpty || s.name.localizedCaseInsensitiveContains(search)
            || (s.siteName ?? "").localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        let sups = model.supervisors.filter(matches)
        let active = sups.filter(\.active), hidden = sups.filter { !$0.active }
        HStack(spacing: 0) {
            List {
                if !active.isEmpty {
                    Section("Supervisors · \(active.count)") { ForEach(active) { row($0) } }
                }
                if !hidden.isEmpty {
                    Section("Hidden · \(hidden.count)") { ForEach(hidden) { row($0) } }
                }
            }
            .listStyle(.inset)
            .overlay {
                if sups.isEmpty {
                    if model.supervisors.isEmpty {
                        ContentUnavailableView {
                            Label("No supervisors yet", systemImage: "person.crop.circle.badge.plus")
                        } description: {
                            Text("Add the people who supervise you, then log supervision with them here.")
                        } actions: {
                            Button("Add Supervisor") { adding = true }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .frame(width: 320)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            Group {
                if let id = selectedId, let s = model.supervisors.first(where: { $0.id == id }) {
                    SupervisorDetail(sup: s).id(s.id)
                } else {
                    EmptyHint(title: "No supervisor selected", icon: "person.crop.circle.badge.checkmark",
                              message: "Pick a supervisor to see your supervision with them and add more.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Supervisors")
        .searchable(text: $search, placement: .toolbar, prompt: "Search supervisors")
        .toolbar {
            ToolbarItem {
                Button { adding = true } label: { Label("Add Supervisor", systemImage: "plus") }
                    .help("Add a supervisor")
            }
        }
        .sheet(isPresented: $adding) { SupervisorSheet(sup: nil) }
        .onAppear {
            if selectedId == nil { selectedId = (active.first ?? sups.first)?.id }
        }
    }

    private func row(_ s: Supervisor) -> some View {
        let selected = selectedId == s.id
        return Button { selectedId = s.id } label: {
            HStack(spacing: 10) {
                Avatar(name: s.name, size: 30).opacity(s.active ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name).fontWeight(.medium)
                    Text("\(s.shortType) · \(s.nSessions) session\(s.nSessions == 1 ? "" : "s") · \(hoursText(s.minutes)) h")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .listRowSeparator(.hidden)
        .contextMenu {
            Button("Add Supervision…") { selectedId = s.id; model.pendingSupervision = s.id }
            Button("Add Several…") { model.batchSessions = WhoRef(who: nil, supervisorId: s.id) }
        }
    }
}

struct SupervisorDetail: View {
    @Environment(AppModel.self) private var model
    let sup: Supervisor
    @State private var selection = Set<Int>()
    @State private var editing = false

    private var entries: [Entry] {
        _ = model.revision
        return ((try? model.repo?.entries(supervisorId: sup.id)) ?? nil) ?? []
    }

    var body: some View {
        let es = entries
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Avatar(name: sup.name, size: 60).opacity(sup.active ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(sup.name).font(.system(size: 26, weight: .bold, design: .rounded))
                        if !sup.active { Pill(text: "Hidden", color: .secondary) }
                    }
                    FlowLayout(spacing: 6) {
                        Pill(text: sup.shortType, color: HourCategory.supervision.color, icon: "person.fill.checkmark")
                        if let site = sup.siteName { Pill(text: site, icon: "building.2") }
                    }
                    Text("\(sup.nSessions) session\(sup.nSessions == 1 ? "" : "s")"
                         + (sup.lastSeen.map { " · last \(Day.medium($0))" } ?? "")
                         + (sup.nPlanned > 0 ? " · \(sup.nPlanned) planned" : ""))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                actions(compact: false)
                actions(compact: true)
            }

            HStack(spacing: 12) {
                StatCard(title: "Total supervision", value: hoursText(sup.minutes), icon: HourCategory.supervision.icon,
                         color: HourCategory.supervision.color)
                StatCard(title: "Individual", value: hoursText(sup.individualMinutes), icon: "person.fill", color: .orange)
                StatCard(title: "Group", value: hoursText(sup.groupMinutes), icon: "person.3.fill", color: .brown)
            }

            EntryTable(entries: es, selection: $selection, showWho: false)
                .overlay {
                    if es.isEmpty {
                        EmptyHint(title: "No supervision yet", icon: "person.2",
                                  message: "Add supervision with \(sup.name) using the buttons above.")
                    }
                }
        }
        .padding(24)
        .sheet(isPresented: $editing) { SupervisorSheet(sup: sup) }
    }

    private func actions(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { model.pendingSupervision = sup.id } label: {
                Label(compact ? "Add" : "Add Supervision", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent).tint(HourCategory.supervision.color)
            .help("Log a supervision session with \(sup.name)")
            Button { model.batchSessions = WhoRef(who: nil, supervisorId: sup.id) } label: {
                Label("Add Several…", systemImage: "calendar.badge.plus")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .help("Add several supervision sessions at once")
            Button { editing = true } label: {
                Label("Edit Supervisor…", systemImage: "pencil")
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .help("Edit name, type or site")
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: !compact, vertical: false)
    }
}

/// Log one supervision session with a given supervisor.
struct NewSupervisionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let supervisorId: Int
    @State private var draft = EntryDraft()
    @State private var ready = false

    var body: some View {
        let name = model.supervisors.first { $0.id == supervisorId }?.name ?? "Supervisor"
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Supervision").font(.title2.bold())
                Text("with \(name)").foregroundStyle(.secondary)
            }
            if ready { EntryFormView(draft: $draft, mode: .log, lockCategory: true) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Supervision") {
                    var d = draft
                    if model.log(&d) { dismiss() }
                }
                .buttonStyle(.borderedProminent).tint(HourCategory.supervision.color)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear {
            var d = EntryDraft()
            d.category = .supervision
            d.supervisorId = supervisorId
            d.activity = Vocab.supervisionTypes[0]
            d.siteId = model.supervisors.first { $0.id == supervisorId }?.siteId ?? model.activeSites.first?.id
            model.applySupervisorDefaults(&d)
            draft = d
            ready = true
        }
    }
}
