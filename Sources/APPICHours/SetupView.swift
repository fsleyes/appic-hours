import AppKit
import SwiftUI
import TrackerCore

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var editingSite: Site?
    @State private var newSite = false
    @State private var editingSup: Supervisor?
    @State private var newSup = false
    @State private var newInstrument = ""
    @State private var renaming: Instrument?
    @State private var renameText = ""
    @State private var editingSemester: Semester?
    @State private var newSemester = false

    var body: some View {
        Form {
            Section {
                ForEach(model.sites) { s in
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.fill").foregroundStyle(.blue).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).fontWeight(.medium)
                            Text([s.settingType, s.degreeProgram, dates(s)].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !s.active { Pill(text: "Hidden") }
                        Button("Edit…") { editingSite = s }
                    }
                }
                Button { newSite = true } label: { Label("Add Site…", systemImage: "plus") }
            } header: {
                Text("Practicum Sites")
            } footer: {
                if model.sites.isEmpty { Text("Start here — every session belongs to a site.") }
            }

            Section("Supervisors") {
                ForEach(model.supervisors) { s in
                    HStack(spacing: 12) {
                        Avatar(name: s.name, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).fontWeight(.medium)
                            Text([s.shortType, s.siteName ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !s.active { Pill(text: "Hidden") }
                        Button("Edit…") { editingSup = s }
                    }
                }
                Button { newSup = true } label: { Label("Add Supervisor…", systemImage: "plus") }
            }

            Section {
                ForEach(model.semesters.reversed()) { s in
                    HStack(spacing: 12) {
                        Image(systemName: "graduationcap.fill")
                            .foregroundStyle(s.contains(Day.today()) ? Color.green : Color.indigo).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(s.name).fontWeight(.medium)
                                if s.contains(Day.today()) { Pill(text: "Now", color: .green) }
                            }
                            Text([s.rangeText,
                                  s.supervisorName.map { $0 + (s.supervisorId == nil ? " (from supervision)" : "") },
                                  s.sessions > 0 ? "\(hoursText(s.minutes)) h" : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit…") { editingSemester = s }
                    }
                }
                HStack {
                    Button { newSemester = true } label: { Label("Add Semester…", systemImage: "plus") }
                    if model.semesters.isEmpty {
                        Menu("Use a Preset") {
                            ForEach(SemesterPreset.allCases) { p in
                                Button(p.title) {
                                    var n = 0
                                    if model.run({ r in n = try r.addSemesters(p.semesters) }) {
                                        model.showToast("Added \(n) semesters")
                                    }
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
            } header: {
                Text("Semesters")
            } footer: {
                Text("Add each semester's first day (usually the first day of classes); it runs until the next one starts. Its supervisor is whoever you had the most supervision with, unless you pick one, and supervision with a neighboring semester's supervisor counts toward that semester.")
            }

            Section {
                FlowLayout(spacing: 6) {
                    ForEach(model.instruments) { i in
                        Text(i.name)
                            .font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.purple.opacity(i.active ? 0.14 : 0.05), in: Capsule())
                            .foregroundStyle(i.active ? Color.primary : Color.secondary)
                            .strikethrough(!i.active)
                            .contextMenu {
                                Button("Rename…") { renaming = i; renameText = i.name }
                                Button(i.active ? "Hide" : "Show") {
                                    model.run { r in try r.updateInstrument(id: i.id, name: i.name, active: !i.active) }
                                }
                            }
                    }
                }
                HStack {
                    TextField("Add instrument", text: $newInstrument, prompt: Text("e.g. WAIS-IV, PAI, SCID-5"))
                        .onSubmit(addInstrument)
                    Button("Add", action: addInstrument).disabled(newInstrument.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Assessment Instruments")
            } footer: {
                Text("Right-click an instrument to rename or hide it.")
            }

            Section {
                DatePicker("Internship start date",
                           selection: .iso({ model.repo?.internshipStart() }, { v in model.run { r in try r.setMeta("internship_start", v) } }),
                           displayedComponents: .date)
            } header: {
                Text("Internship")
            } footer: {
                Text("Used to project anticipated hours on the AAPI Summary.")
            }

            Section {
                LabeledContent("Data folder") {
                    Text(model.config.dataURL.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                HStack {
                    Button("Show in Finder") { model.revealInFinder(model.config.dbURL) }
                    Button("Move Data Folder…", action: moveData)
                    Button("Back Up Now") {
                        if let db = model.repo?.db, let u = try? Schema.backup(db, to: model.config.backupURL) {
                            model.showToast("Backed up to \(u.lastPathComponent)")
                        }
                    }
                }
                LabeledContent("Exports") {
                    Text(model.config.exportURL.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                Button("Change Export Folder…", action: changeExport)
            } header: {
                Text("Data & Privacy")
            } footer: {
                Label("The app never stores client data inside itself. Daily backups are kept in the data folder (last 30). Use pseudonyms only — no names, birthdates or contact details.",
                      systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup")
        .sheet(isPresented: $newSite) { SiteSheet(site: nil) }
        .sheet(item: $editingSite) { SiteSheet(site: $0) }
        .sheet(isPresented: $newSup) { SupervisorSheet(sup: nil) }
        .sheet(item: $editingSup) { SupervisorSheet(sup: $0) }
        .sheet(isPresented: $newSemester) { SemesterSheet(semester: nil) }
        .sheet(item: $editingSemester) { SemesterSheet(semester: $0) }
        .alert("Rename instrument", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let i = renaming { model.run { r in try r.updateInstrument(id: i.id, name: renameText, active: i.active) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func dates(_ s: Site) -> String {
        switch (s.startDate, s.endDate) {
        case let (a?, b?): return "\(Day.medium(a)) – \(Day.medium(b))"
        case let (a?, nil): return "since \(Day.medium(a))"
        case let (nil, b?): return "until \(Day.medium(b))"
        default: return ""
        }
    }

    private func addInstrument() {
        let n = newInstrument
        if model.run({ r in try r.addInstrument(n) }) { newInstrument = "" }
    }

    private func moveData() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Move Here"
        guard p.runModal() == .OK, let url = p.url, let db = model.repo?.db else { return }
        do {
            try AppConfig.validate(url)
            let target = url.appendingPathComponent(AppConfig.dbName)
            if FileManager.default.fileExists(atPath: target.path) {
                model.alert = "\(target.path) already exists. Pick an empty folder."
                return
            }
            try db.backup(to: target.path)
            let old = model.config.dataURL
            model.config.dataDir = url.path
            try model.config.save()
            model.repo = nil
            model.open()
            let a = NSAlert()
            a.messageText = "Data folder moved"
            a.informativeText = "Your data was copied to \(url.path) and the app is now using it.\n\nThe old copy is still in \(old.path) — delete it yourself once you've checked the new one."
            a.runModal()
        } catch {
            model.alert = error.localizedDescription
        }
    }

    private func changeExport() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try AppConfig.validate(url)
            model.config.exportDir = url.path
            try model.config.save()
        } catch { model.alert = error.localizedDescription }
    }
}

struct SiteSheet: View {
    @Environment(AppModel.self) private var model
    let site: Site?
    @State private var name = ""
    @State private var type = Vocab.settingTypes[2]
    @State private var degree = "Doctoral"
    @State private var hasStart = false
    @State private var start = Date()
    @State private var hasEnd = false
    @State private var end = Date()
    @State private var notes = ""
    @State private var active = true

    var body: some View {
        SheetScaffold(title: site == nil ? "New Site" : "Edit Site", confirm: site == nil ? "Add Site" : "Save",
                      confirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
            let s = hasStart ? Day.iso(start) : nil, e = hasEnd ? Day.iso(end) : nil
            return model.run { r in
                if let site {
                    try r.updateSite(id: site.id, name: name, settingType: type, degreeProgram: degree,
                                     startDate: s, endDate: e, notes: notes, active: active)
                } else {
                    try r.addSite(name: name, settingType: type, degreeProgram: degree, startDate: s, endDate: e, notes: notes)
                }
            }
        } content: {
            Form {
                TextField("Site name", text: $name, prompt: Text("e.g. University Training Clinic"))
                Picker("AAPI setting type", selection: $type) {
                    ForEach(Vocab.settingTypes, id: \.self) { Text($0).tag($0) }
                }
                Picker("Degree program", selection: $degree) {
                    ForEach(Vocab.degrees, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Start date", isOn: $hasStart)
                if hasStart { DatePicker("Started", selection: $start, displayedComponents: .date) }
                Toggle("End date", isOn: $hasEnd)
                if hasEnd { DatePicker("Ended", selection: $end, displayedComponents: .date) }
                TextField("Notes", text: $notes, prompt: Text("Optional"))
                if site != nil { Toggle("Show in pickers", isOn: $active) }
            }
            .formStyle(.grouped).frame(height: 420)
        }
        .onAppear {
            guard let s = site else { return }
            name = s.name; type = s.settingType; degree = s.degreeProgram; notes = s.notes ?? ""; active = s.active
            if let d = s.startDate.flatMap(Day.date) { hasStart = true; start = d }
            if let d = s.endDate.flatMap(Day.date) { hasEnd = true; end = d }
        }
    }
}

struct SupervisorSheet: View {
    @Environment(AppModel.self) private var model
    let sup: Supervisor?
    @State private var name = ""
    @State private var type = Vocab.supervisorTypes[0]
    @State private var siteId: Int?
    @State private var active = true

    var body: some View {
        SheetScaffold(title: sup == nil ? "New Supervisor" : "Edit Supervisor", confirm: sup == nil ? "Add" : "Save",
                      confirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
            model.run { r in
                if let sup {
                    try r.updateSupervisor(id: sup.id, name: name, supervisorType: type, siteId: siteId, active: active)
                } else {
                    try r.addSupervisor(name: name, supervisorType: type, siteId: siteId)
                }
            }
        } content: {
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Dr. Rivera"))
                Picker("Type", selection: $type) {
                    ForEach(Vocab.supervisorTypes, id: \.self) { Text(Vocab.supervisorTypeShort[$0] ?? $0).tag($0) }
                }
                Picker("Site", selection: $siteId) {
                    Text("Any").tag(Int?.none)
                    ForEach(model.sites) { Text($0.name).tag(Int?.some($0.id)) }
                }
                if sup != nil { Toggle("Show in pickers", isOn: $active) }
            }
            .formStyle(.grouped).frame(height: 220)
        }
        .onAppear {
            guard let s = sup else { siteId = model.activeSites.first?.id; return }
            name = s.name; type = s.supervisorType; siteId = s.siteId; active = s.active
        }
    }
}

struct SemesterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let semester: Semester?
    @State private var name = ""
    @State private var start = Day.today()
    @State private var supervisorId: Int?
    @State private var confirmDelete = false

    var body: some View {
        SheetScaffold(title: semester == nil ? "New Semester" : "Edit Semester",
                      subtitle: "It runs until the next semester starts.",
                      confirm: semester == nil ? "Add" : "Save",
                      confirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty, width: 480) {
            model.run { r in
                if let semester {
                    try r.updateSemester(id: semester.id, name: name, start: start, supervisorId: supervisorId)
                } else {
                    try r.addSemester(name: name, start: start, supervisorId: supervisorId)
                }
            }
        } content: {
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. Fall 2027"))
                DatePicker("Starts", selection: .iso({ start }, { start = $0 }), displayedComponents: .date)
                Picker("Supervisor", selection: $supervisorId) {
                    Text(autoLabel).tag(Int?.none)
                    Divider()
                    ForEach(model.supervisors) { Text($0.name).tag(Int?.some($0.id)) }
                }
                if let semester {
                    Button("Delete Semester…", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete \(semester.name)?", isPresented: $confirmDelete) {
                            Button("Delete", role: .destructive) {
                                if model.run({ r in try r.deleteSemester(id: semester.id) }) { dismiss() }
                            }
                        } message: {
                            Text("No sessions are deleted — they'll count toward the semester before it instead.")
                        }
                }
            }
            .formStyle(.grouped).frame(height: semester == nil ? 150 : 180)
        }
        .onAppear {
            if let s = semester { name = s.name; start = s.start; supervisorId = s.supervisorId }
            else if let next = model.repo?.suggestedNextSemester() { name = next.name; start = next.start }
        }
    }

    private var autoLabel: String {
        guard let s = semester, let auto = s.autoSupervisorId,
              let n = model.supervisors.first(where: { $0.id == auto })?.name else { return "Automatic (from supervision)" }
        return "Automatic — \(n)"
    }
}
