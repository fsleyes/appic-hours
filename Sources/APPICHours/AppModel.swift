import AppKit
import SwiftUI
import TrackerCore

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case log, sessions, clients, supervisors, calendar, recurring, summary, setup
    var id: String { rawValue }
    var title: String {
        switch self {
        case .log: return "Log"
        case .sessions: return "Sessions"
        case .clients: return "Clients"
        case .supervisors: return "Supervisors"
        case .calendar: return "Calendar"
        case .recurring: return "Recurring"
        case .summary: return "AAPI Summary"
        case .setup: return "Setup"
        }
    }
    var icon: String {
        switch self {
        case .log: return "square.and.pencil"
        case .sessions: return "list.bullet.rectangle"
        case .clients: return "person.2"
        case .supervisors: return "person.crop.circle.badge.checkmark"
        case .calendar: return "calendar"
        case .recurring: return "repeat"
        case .summary: return "chart.bar.xaxis"
        case .setup: return "gearshape"
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var undoEntryIds: [Int] = []
    var undoRestore: [Int: EntryInput] = [:]   // entry id → previous values
    var canUndo: Bool { !undoEntryIds.isEmpty || !undoRestore.isEmpty }
}

struct EditRef: Identifiable, Hashable { let id: Int }
struct RecapRef: Identifiable, Hashable { let id: String }   // id = the recap week's Friday

/// Something waiting for a ✓/✗: a recurring occurrence, or a planned session whose date has come.
enum ConfirmItem: Identifiable, Hashable {
    case slot(SlotOccurrence)
    case planned(Entry)
    var id: String {
        switch self {
        case .slot(let o): return "s\(o.id)"
        case .planned(let e): return "p\(e.id)"
        }
    }
    var date: String {
        switch self {
        case .slot(let o): return o.date
        case .planned(let e): return e.date
        }
    }
}
struct BulkRef: Identifiable, Hashable { let ids: [Int]; var id: String { ids.map(String.init).joined(separator: ",") } }
struct WhoRef: Identifiable, Hashable {
    let who: Who?
    var supervisorId: Int? = nil        // batch-adding supervision with this supervisor
    var id: String { "\(String(describing: who))-\(supervisorId ?? -1)" }
}

/// The session-entry form's state (shared by Log, quick-log, edit, recurring and batch).
struct EntryDraft: Equatable {
    var category: HourCategory = .intervention
    var date = Date()
    var who: Who?
    var supervisorId: Int?
    var activity = Vocab.individualTherapy
    var siteId: Int?
    var minutes = 60
    var modality = Vocab.defaultModality
    var purpose = "Clinical"
    var instrumentIds: Set<Int> = []
    var specify = ""
    var note = ""
    // recurring-slot fields
    var weekday = Day.weekday(Day.today())
    var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    var startDate = Date()

    var usesWho: Bool { category != .supervision }

    func input(date override: String? = nil, minutes m: Int? = nil, note n: String? = nil) -> EntryInput {
        let who = usesWho ? who : nil
        return EntryInput(
            date: override ?? Day.iso(date), siteId: siteId, category: category, activity: activity,
            minutes: m ?? minutes, modality: modality, clientId: who?.clientId, groupId: who?.groupId,
            supervisorId: category == .supervision ? supervisorId : nil,
            purpose: category == .assessment ? purpose : nil,
            specify: specify.isEmpty ? nil : specify, note: n ?? (note.isEmpty ? nil : note),
            instrumentIds: category == .assessment ? Array(instrumentIds) : [])
    }

    init() {}

    init(entry e: Entry, instrumentIds: [Int]) {
        category = e.category
        date = Day.date(e.date) ?? Date()
        if let c = e.clientId { who = .client(c) } else if let g = e.groupId { who = .group(g) }
        supervisorId = e.supervisorId
        activity = e.activity
        siteId = e.siteId
        minutes = e.minutes
        modality = e.modality
        purpose = e.purpose ?? "Clinical"
        self.instrumentIds = Set(instrumentIds)
        specify = e.specify ?? ""
        note = e.note ?? ""
    }
}

@Observable @MainActor
final class AppModel {
    static var shared: AppModel?

    var config = AppConfig.load()
    var repo: Repo?
    var openError: String?

    var section: SidebarItem? = .log

    // cached data (cheap to reload — SQLite is local)
    var sites: [Site] = []
    var supervisors: [Supervisor] = []
    var instruments: [Instrument] = []
    var clients: [Client] = []
    var groups: [ClientGroup] = []
    var recent: [Entry] = []
    var slots: [Slot] = []
    var pending: [SlotOccurrence] = []
    var duePlanned: [Entry] = []         // planned sessions whose date has arrived
    var upcomingPlanned = 0              // planned sessions still in the future
    var recentWho: [Who] = []
    var semesters: [Semester] = []
    var totalCount = 0
    var totalMinutes = 0
    var daysSinceLast: Int?
    var revision = 0

    // UI state
    var toast: Toast?
    var alert: String?
    var logDraft = EntryDraft()
    var quickDraft = EntryDraft()
    var clientSelection: Who?
    var editing: EditRef?
    var bulkEdit: BulkRef?
    var pendingSupervision: Int?     // supervisor id → "Add Supervision" sheet
    var editWho: WhoRef?          // client/group whose details are being edited
    var batchSessions: WhoRef?
    var showBatchClients = false
    var showNewClient = false
    var showNewSlot = false
    var pendingDelete: Who?
    var exportRequest = 0
    var recap: RecapRef?

    init() {
        AppModel.shared = self
        if config.isConfigured { open() }
    }

    var isReady: Bool { repo != nil }
    var semesterIndex: SemesterIndex { SemesterIndex(semesters) }
    func semester(for e: Entry) -> Semester? { semesterIndex.semester(for: e) }
    func semester(containing date: String) -> Semester? { semesterIndex.index(date: date).map { semesterIndex.semesters[$0] } }
    var hasTerminalMasters: Bool { sites.contains { $0.degreeProgram == "Terminal Masters" } }
    var activeSites: [Site] { sites.filter(\.active) }
    var activeSupervisors: [Supervisor] { supervisors.filter(\.active) }
    var activeInstruments: [Instrument] { instruments.filter(\.active) }
    var openClients: [Client] { clients.filter { !$0.isClosed } }
    var openGroups: [ClientGroup] { groups.filter { !$0.isClosed } }

    // MARK: lifecycle

    func open() {
        do {
            try config.ensureDirs()
            try Schema.backupBeforeUpgrade(dbPath: config.dbURL.path, backupDir: config.backupURL)
            let db = try Schema.open(config.dbURL.path)
            repo = Repo(db)
            _ = try? Schema.backup(db, to: config.backupURL)
            openError = nil
            reload()
        } catch {
            openError = "Couldn't open your data folder (\(config.dataURL.path)): \(error.localizedDescription)"
        }
    }

    func chooseDataFolder(_ url: URL) throws {
        try AppConfig.validate(url)
        config.dataDir = url.path
        try config.save()
        open()
    }

    // MARK: weekly recap

    /// Opens the latest finished week's recap if it hasn't been seen (called on launch and whenever the app
    /// comes to the front). Waits while another sheet is up.
    func checkRecap() {
        guard let r = repo, recap == nil, editing == nil, bulkEdit == nil, batchSessions == nil,
              pendingSupervision == nil, !showBatchClients else { return }
        let friday = WeekRecap.lastCompletedFriday()
        guard (r.meta("recap_seen") ?? "") < friday, let first = r.firstRecapFriday(), first <= friday else { return }
        recap = RecapRef(id: friday)
    }

    func showRecap() { recap = RecapRef(id: WeekRecap.lastCompletedFriday()) }

    func recapDismissed() {
        let friday = WeekRecap.lastCompletedFriday()
        if let r = repo, (r.meta("recap_seen") ?? "") < friday { try? r.setMeta("recap_seen", friday) }
    }

    func backupOnQuit() {
        if let db = repo?.db { _ = try? Schema.backup(db, to: config.backupURL) }
    }

    func reload() {
        guard let r = repo else { return }
        let today = Day.today()
        sites = (try? r.sites()) ?? []
        supervisors = (try? r.supervisors()) ?? []
        instruments = (try? r.instruments()) ?? []
        clients = (try? r.clients()) ?? []
        groups = (try? r.groups()) ?? []
        recent = (try? r.entries(limit: 200)) ?? []
        slots = (try? r.slots()) ?? []
        pending = (try? r.pendingSlotOccurrences(from: "0000-01-01", to: today)) ?? []   // every unconfirmed occurrence since each slot began
        duePlanned = (try? r.duePlanned(today: today)) ?? []
        upcomingPlanned = r.upcomingPlannedCount(today: today)
        recentWho = (try? r.recentTargets()) ?? []
        semesters = (try? r.semesters()) ?? []
        let t = r.totals()
        totalCount = t.count
        totalMinutes = t.minutes
        daysSinceLast = r.daysSinceLastEntry()
        if logDraft.siteId == nil { logDraft.siteId = activeSites.first?.id }
        if quickDraft.siteId == nil { quickDraft.siteId = activeSites.first?.id }
        revision += 1
    }

    /// Run a write; show any error; reload. Returns success.
    @discardableResult
    func run(_ body: (Repo) throws -> Void) -> Bool {
        guard let r = repo else { return false }
        do {
            try body(r)
            reload()
            return true
        } catch {
            alert = error.localizedDescription
            reload()
            return false
        }
    }

    // MARK: lookups

    func client(_ id: Int?) -> Client? { id.flatMap { i in clients.first { $0.id == i } } }
    func group(_ id: Int?) -> ClientGroup? { id.flatMap { i in groups.first { $0.id == i } } }
    func site(_ id: Int?) -> Site? { id.flatMap { i in sites.first { $0.id == i } } }

    func label(_ who: Who?) -> String {
        switch who {
        case .client(let id): return client(id)?.code ?? "?"
        case .group(let id): return group(id)?.name ?? "?"
        case nil: return "No client"
        }
    }

    func isClosed(_ who: Who?) -> Bool {
        switch who {
        case .client(let id): return client(id)?.isClosed ?? false
        case .group(let id): return group(id)?.isClosed ?? false
        case nil: return false
        }
    }

    /// Open clients/groups, most recently seen first.
    func recentOpen(_ n: Int = 6) -> [Who] {
        Array(recentWho.filter { !isClosed($0) && label($0) != "?" }.prefix(n))
    }

    // MARK: entry-form logic

    func activities(for d: EntryDraft) -> [String] {
        let all = Vocab.activities(for: d.category)
        guard d.category == .intervention else { return all }
        if case .group(let gid) = d.who, let g = group(gid) {
            return Vocab.groupServiceToGroupType.filter { $0.value == g.groupType }.map(\.key)
        }
        return all.filter { Vocab.groupServiceToGroupType[$0] == nil }
    }

    func normalizeActivity(_ d: inout EntryDraft) {
        let opts = activities(for: d)
        if !opts.contains(d.activity) { d.activity = opts.first ?? "" }
    }

    /// Picking a client fills site, and the activity/duration/modality used last time.
    func applyWhoDefaults(_ d: inout EntryDraft) {
        defer { normalizeActivity(&d) }
        guard let who = d.who, let r = repo else { return }
        switch who {
        case .client(let id): if let c = client(id) { d.siteId = c.siteId }
        case .group(let id): if let g = group(id) { d.siteId = g.siteId }
        }
        guard let last = try? r.lastEntry(clientId: who.clientId, groupId: who.groupId) else { return }
        let direct: Set<HourCategory> = [.intervention, .assessment]
        if direct.contains(d.category) && direct.contains(last.category) && last.category != d.category {
            d.category = last.category
        }
        guard last.category == d.category else { return }
        d.activity = last.activity
        d.minutes = last.minutes
        d.modality = last.modality
        d.siteId = last.siteId
        if last.category == .assessment, let p = last.purpose { d.purpose = p }
    }

    func applySupervisorDefaults(_ d: inout EntryDraft) {
        guard let sid = d.supervisorId, let r = repo else { return }
        if let last = try? r.lastEntry(supervisorId: sid) {
            d.activity = last.activity
            d.minutes = last.minutes
            d.siteId = last.siteId
            d.modality = last.modality
        } else if let s = supervisors.first(where: { $0.id == sid }), let site = s.siteId {
            d.siteId = site
        }
        normalizeActivity(&d)
    }

    // MARK: actions

    func log(_ d: inout EntryDraft) -> Bool {
        guard let r = repo else { return false }
        do {
            let id = try r.addEntry(d.input())
            reload()
            if let e = try r.entry(id) {
                let who = e.who.isEmpty ? "" : " · \(e.who)"
                if e.planned {
                    showToast("Planned \(AAPI.fmt(e.hours)) h\(who) for \(Day.medium(e.date)) — it counts once you confirm it then",
                              undo: [id])
                } else {
                    showToast("Logged \(AAPI.fmt(e.hours)) h · \(e.activity)\(who) · \(Day.medium(e.date))", undo: [id])
                }
            }
            // keep date/category/site — likely the same next time; clear the rest
            d.who = nil
            d.note = ""
            d.specify = ""
            d.instrumentIds = []
            return true
        } catch {
            alert = error.localizedDescription
            return false
        }
    }

    func showToast(_ message: String, undo: [Int] = [], restore: [Int: EntryInput] = [:]) {
        let t = Toast(message: message, undoEntryIds: undo, undoRestore: restore)
        withAnimation(.snappy) { toast = t }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            if toast?.id == t.id { withAnimation(.snappy) { toast = nil } }
        }
    }

    func undoToast() {
        guard let t = toast else { return }
        run { r in
            try r.db.transaction {
                for id in t.undoEntryIds { try r.deleteEntry(id: id) }
                for (id, input) in t.undoRestore { try r.updateEntry(id: id, input) }
            }
        }
        withAnimation(.snappy) { toast = nil }
    }

    func duplicateToToday(_ id: Int) {
        run { r in
            guard let e = try r.entry(id) else { return }
            var input = EntryDraft(entry: e, instrumentIds: try r.entryInstrumentIds(id)).input(date: Day.today())
            input.note = nil
            try r.addEntry(input)
        }
        showToast("Duplicated to today")
    }

    func confirm(_ o: SlotOccurrence) {
        run { r in try r.confirmSlot(id: o.slot.id, date: o.date) }
    }

    func skip(_ o: SlotOccurrence) {
        run { r in try r.skipSlot(id: o.slot.id, date: o.date) }
    }

    func confirmAll() {
        let n = toConfirmCount
        let planned = duePlanned.map(\.id)
        run { r in
            try r.db.transaction {
                for o in pending { try r.confirmSlot(id: o.slot.id, date: o.date) }
                try r.confirmPlanned(ids: planned)
            }
        }
        showToast("Confirmed \(n) session\(n == 1 ? "" : "s")")
    }

    // MARK: confirming

    var toConfirm: [ConfirmItem] {
        (pending.map(ConfirmItem.slot) + duePlanned.map(ConfirmItem.planned)).sorted { $0.date < $1.date }
    }
    var toConfirmCount: Int { pending.count + duePlanned.count }

    func confirmPlanned(_ e: Entry) {
        run { r in try r.confirmPlanned(ids: [e.id]) }
    }

    /// Planned session that didn't happen: remove it.
    func dropPlanned(_ e: Entry) {
        run { r in try r.deleteEntry(id: e.id) }
        showToast("Removed the planned \(Day.medium(e.date)) session")
    }

    func startLog(for who: Who) {
        // assessment clients start on an Assessment session
        logDraft.category = client(who.clientId)?.kind == .assessment ? .assessment : .intervention
        logDraft.who = who
        applyWhoDefaults(&logDraft)
        section = .log
    }

    // MARK: reminders

    var bannerMessages: [String] {
        guard isReady else { return [] }
        if sites.isEmpty {
            return ["Start in Setup: add your practicum site, then add clients."]
        }
        var m: [String] = []
        if let d = daysSinceLast, d >= 3 { m.append("Nothing logged in \(d) days.") }
        if toConfirmCount > 0 {
            m.append("\(toConfirmCount) session\(toConfirmCount == 1 ? "" : "s") to confirm.")
        }
        return m
    }

    // MARK: files

    func revealInFinder(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
