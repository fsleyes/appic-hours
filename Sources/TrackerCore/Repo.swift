import Foundation

/// Data access + validation. All writes go through here.
public final class Repo {
    public let db: Database

    public init(_ db: Database) { self.db = db }

    // MARK: helpers

    static func blank(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func check(_ cond: Bool, _ msg: @autoclosure () -> String) throws {
        if !cond { throw ValidationError(msg()) }
    }

    static func isoOrNil(_ s: String?) throws -> String? {
        guard let s = blank(s) else { return nil }
        let d = String(s.prefix(10))
        try check(Day.isValid(d), "Invalid date: \(s)")
        return d
    }

    // MARK: meta

    public func meta(_ key: String) -> String? {
        (try? db.one("SELECT value FROM meta WHERE key=?", [key]))?.str("value")
    }

    public func setMeta(_ key: String, _ value: String?) throws {
        try db.run("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                   [key, value])
    }

    public func internshipStart(today: String = Day.today()) -> String {
        if let v = meta("internship_start"), Day.isValid(v) { return v }
        let y = Day.year(today), m = Day.month(today)
        return String(format: "%04d-07-01", m >= 7 ? y + 1 : y)
    }

    // MARK: sites

    public func sites(activeOnly: Bool = false) throws -> [Site] {
        try db.query("SELECT * FROM site" + (activeOnly ? " WHERE active=1" : "") + " ORDER BY name")
            .map(Site.init)
    }

    private func validateSite(_ name: String, _ type: String, _ degree: String) throws {
        try Self.check(Self.blank(name) != nil, "Site name is required.")
        try Self.check(Vocab.settingTypes.contains(type), "Unknown setting type: '\(type)'")
        try Self.check(Vocab.degrees.contains(degree), "Unknown degree program: '\(degree)'")
    }

    @discardableResult
    public func addSite(name: String, settingType: String, degreeProgram: String = "Doctoral",
                        startDate: String? = nil, endDate: String? = nil, notes: String? = nil) throws -> Int {
        try validateSite(name, settingType, degreeProgram)
        do {
            return try db.run("INSERT INTO site(name,setting_type,degree_program,start_date,end_date,notes) VALUES(?,?,?,?,?,?)",
                              [Self.trim(name), settingType, degreeProgram, try Self.isoOrNil(startDate),
                               try Self.isoOrNil(endDate), Self.blank(notes)])
        } catch let e as DBError where e.isConstraint {
            throw ValidationError("A site named '\(Self.trim(name))' already exists.")
        }
    }

    public func updateSite(id: Int, name: String, settingType: String, degreeProgram: String,
                           startDate: String? = nil, endDate: String? = nil, notes: String? = nil,
                           active: Bool = true) throws {
        try validateSite(name, settingType, degreeProgram)
        do {
            try db.run("UPDATE site SET name=?,setting_type=?,degree_program=?,start_date=?,end_date=?,notes=?,active=? WHERE id=?",
                       [Self.trim(name), settingType, degreeProgram, try Self.isoOrNil(startDate),
                        try Self.isoOrNil(endDate), Self.blank(notes), active, id])
        } catch let e as DBError where e.isConstraint {
            throw ValidationError("A site named '\(Self.trim(name))' already exists.")
        }
    }

    public func siteId(named name: String) -> Int? {
        (try? db.one("SELECT id FROM site WHERE name=? COLLATE NOCASE", [Self.trim(name)]))?.int("id")
    }

    // MARK: supervisors

    public func supervisors(activeOnly: Bool = false) throws -> [Supervisor] {
        try db.query("""
            SELECT sv.*, s.name AS site_name,
            (SELECT COUNT(*) FROM entry e WHERE e.supervisor_id=sv.id AND e.planned=0) AS n_sessions,
            (SELECT COALESCE(SUM(minutes),0) FROM entry e WHERE e.supervisor_id=sv.id AND e.planned=0) AS minutes,
            (SELECT COALESCE(SUM(minutes),0) FROM entry e WHERE e.supervisor_id=sv.id AND e.planned=0
                AND e.activity='Individual Supervision') AS individual_minutes,
            (SELECT COALESCE(SUM(minutes),0) FROM entry e WHERE e.supervisor_id=sv.id AND e.planned=0
                AND e.activity='Group Supervision') AS group_minutes,
            (SELECT MAX(date) FROM entry e WHERE e.supervisor_id=sv.id AND e.planned=0) AS last_seen,
            (SELECT COUNT(*) FROM entry e WHERE e.supervisor_id=sv.id AND e.planned=1) AS n_planned
            FROM supervisor sv LEFT JOIN site s ON s.id = sv.site_id
            """ + (activeOnly ? " WHERE sv.active=1" : "") + " ORDER BY sv.name").map(Supervisor.init)
    }

    @discardableResult
    public func addSupervisor(name: String, supervisorType: String, siteId: Int? = nil) throws -> Int {
        try Self.check(Self.blank(name) != nil, "Supervisor name is required.")
        try Self.check(Vocab.supervisorTypes.contains(supervisorType), "Unknown supervisor type: '\(supervisorType)'")
        do {
            return try db.run("INSERT INTO supervisor(name,supervisor_type,site_id) VALUES(?,?,?)",
                              [Self.trim(name), supervisorType, siteId])
        } catch let e as DBError where e.isConstraint {
            throw ValidationError("A supervisor named '\(Self.trim(name))' already exists.")
        }
    }

    public func updateSupervisor(id: Int, name: String, supervisorType: String, siteId: Int? = nil,
                                 active: Bool = true) throws {
        try Self.check(Self.blank(name) != nil, "Supervisor name is required.")
        try Self.check(Vocab.supervisorTypes.contains(supervisorType), "Unknown supervisor type: '\(supervisorType)'")
        do {
            try db.run("UPDATE supervisor SET name=?,supervisor_type=?,site_id=?,active=? WHERE id=?",
                       [Self.trim(name), supervisorType, siteId, active, id])
        } catch let e as DBError where e.isConstraint {
            throw ValidationError("A supervisor named '\(Self.trim(name))' already exists.")
        }
    }

    // MARK: clients

    private func validateClient(_ c: ClientInput) throws {
        try Self.check(Self.blank(c.code) != nil, "Client code is required.")
        try Self.check(c.siteId != nil && (try? db.one("SELECT 1 FROM site WHERE id=?", [c.siteId])) != nil,
                       "Client needs a valid site.")
        try Self.check(Vocab.clientAges.contains(c.ageGroup), "Unknown age group: '\(c.ageGroup)'")
        try Self.check(c.race == nil || Vocab.races.contains(c.race!), "Unknown race/ethnicity: '\(c.race ?? "")'")
        try Self.check(c.gender == nil || Vocab.genders.contains(c.gender!), "Unknown gender: '\(c.gender ?? "")'")
        try Self.check(c.orientation == nil || Vocab.orientations.contains(c.orientation!),
                       "Unknown sexual orientation: '\(c.orientation ?? "")'")
        for d in c.disabilities {
            try Self.check(Vocab.disabilities.contains(d), "Unknown disability: '\(d)'")
        }
    }

    private func normalized(_ c: ClientInput) -> ClientInput {
        var c = c
        c.race = Self.blank(c.race); c.gender = Self.blank(c.gender); c.orientation = Self.blank(c.orientation)
        var seen = Set<String>()
        c.disabilities = c.disabilities.filter { seen.insert($0).inserted }
        return c
    }

    private func insertClient(_ input: ClientInput) throws -> Int {
        let c = normalized(input)
        try validateClient(c)
        let cid: Int
        do {
            cid = try db.run("INSERT INTO client(code,site_id,age_group,race,gender,orientation,notes,opened_on,kind) VALUES(?,?,?,?,?,?,?,?,?)",
                             [Self.trim(c.code), c.siteId, c.ageGroup, c.race, c.gender, c.orientation,
                              Self.blank(c.notes), try Self.isoOrNil(c.openedOn), c.kind.rawValue])
        } catch let e as DBError where e.isConstraint {
            throw ValidationError("Client code '\(c.code)' already exists.")
        }
        for d in c.disabilities {
            try db.run("INSERT INTO client_disability(client_id,disability) VALUES(?,?)", [cid, d])
        }
        return cid
    }

    @discardableResult
    public func addClient(_ c: ClientInput) throws -> Int {
        try db.transaction { try insertClient(c) }
    }

    /// Insert many clients atomically: all succeed or none do.
    @discardableResult
    public func addClientsBulk(_ rows: [ClientInput]) throws -> [Int] {
        try db.transaction {
            try rows.enumerated().map { i, r in
                do { return try insertClient(r) } catch let e as ValidationError {
                    throw ValidationError("Row \(i + 1): \(e.message)")
                }
            }
        }
    }

    public func updateClient(id: Int, _ input: ClientInput) throws {
        let c = normalized(input)
        try validateClient(c)
        try db.transaction {
            do {
                try db.run("UPDATE client SET code=?,site_id=?,age_group=?,race=?,gender=?,orientation=?,notes=?,opened_on=?,kind=? WHERE id=?",
                           [Self.trim(c.code), c.siteId, c.ageGroup, c.race, c.gender, c.orientation,
                            Self.blank(c.notes), try Self.isoOrNil(c.openedOn), c.kind.rawValue, id])
            } catch let e as DBError where e.isConstraint {
                throw ValidationError("Client code '\(c.code)' already exists.")
            }
            try db.run("DELETE FROM client_disability WHERE client_id=?", [id])
            for d in c.disabilities {
                try db.run("INSERT INTO client_disability(client_id,disability) VALUES(?,?)", [id, d])
            }
        }
    }

    /// Mark a client's case closed. Their recurring sessions end on the same date.
    public func closeClient(id: Int, closedOn: String? = nil, note: String? = nil) throws {
        let closed = try Self.isoOrNil(closedOn) ?? Day.today()
        try db.transaction {
            try db.run("UPDATE client SET closed_on=?, closure_note=? WHERE id=?", [closed, Self.blank(note), id])
            try db.run("UPDATE slot SET active=0, end_date=? WHERE client_id=? AND active=1", [closed, id])
        }
    }

    /// What deleting would remove (for the confirmation message).
    public func deletionImpact(clientId: Int? = nil, groupId: Int? = nil) throws -> (sessions: Int, minutes: Int, reports: Int) {
        let col = clientId != nil ? "client_id" : "group_id"
        let id = clientId ?? groupId
        let r = try db.one("SELECT COUNT(*) AS n, COALESCE(SUM(minutes),0) AS m FROM entry WHERE \(col)=?", [id])
        let reps = clientId == nil ? 0 : (try db.one("SELECT COUNT(*) AS n FROM report WHERE client_id=?", [clientId])?.int("n") ?? 0)
        return (r?.int("n") ?? 0, r?.int("m") ?? 0, reps)
    }

    /// Permanently delete a client and everything logged for them
    /// (sessions, reports, recurring slots, demographics). Use closeClient to keep hours.
    public func deleteClient(id: Int) throws {
        try db.transaction {
            try db.run("DELETE FROM entry WHERE client_id=?", [id])
            try db.run("DELETE FROM report WHERE client_id=?", [id])
            try db.run("DELETE FROM slot WHERE client_id=?", [id])
            try db.run("DELETE FROM client WHERE id=?", [id])
        }
    }

    /// Permanently delete a group/family/couple and its sessions and recurring slots.
    public func deleteGroup(id: Int) throws {
        try db.transaction {
            try db.run("DELETE FROM entry WHERE group_id=?", [id])
            try db.run("DELETE FROM slot WHERE group_id=?", [id])
            try db.run("DELETE FROM client_group WHERE id=?", [id])
        }
    }

    public func reopenClient(id: Int) throws {
        try db.run("UPDATE client SET closed_on=NULL, closure_note=NULL WHERE id=?", [id])
    }

    private static let clientSelect = """
        SELECT c.*, s.name AS site_name, s.degree_program AS degree,
        (SELECT group_concat(disability, '; ') FROM client_disability d WHERE d.client_id=c.id) AS disabilities,
        (SELECT COUNT(*) FROM entry e WHERE e.client_id=c.id AND e.planned=0) AS n_sessions,
        (SELECT COALESCE(SUM(minutes),0) FROM entry e WHERE e.client_id=c.id AND e.planned=0) AS minutes,
        (SELECT MAX(date) FROM entry e WHERE e.client_id=c.id AND e.planned=0) AS last_seen,
        (SELECT COUNT(*) FROM entry e WHERE e.client_id=c.id AND e.planned=1) AS n_planned,
        CASE WHEN EXISTS (SELECT 1 FROM entry e WHERE e.client_id=c.id AND e.category='intervention') THEN 'therapy'
             WHEN EXISTS (SELECT 1 FROM entry e WHERE e.client_id=c.id AND e.category='assessment') THEN 'assessment'
             ELSE c.kind END AS effective_kind
        FROM client c JOIN site s ON s.id=c.site_id
        """

    public func clients(openOnly: Bool = false) throws -> [Client] {
        try db.query(Self.clientSelect + (openOnly ? " WHERE c.closed_on IS NULL" : "")
                     + " ORDER BY c.code COLLATE NOCASE").map(Client.init)
    }

    public func client(_ id: Int) throws -> Client? {
        try db.one(Self.clientSelect + " WHERE c.id=?", [id]).map(Client.init)
    }

    public func existingClientCodes() throws -> Set<String> {
        Set(try db.query("SELECT code FROM client").compactMap { $0.str("code")?.lowercased() })
    }

    // MARK: groups

    private func validateGroup(_ name: String, _ type: String, _ siteId: Int?, _ age: String?) throws {
        try Self.check(Self.blank(name) != nil, "Group name is required.")
        try Self.check(Vocab.groupTypes.contains(type), "Unknown group type: '\(type)'")
        try Self.check(siteId != nil, "Group needs a site.")
        try Self.check(age == nil || Vocab.groupAges.contains(age!), "Unknown group age: '\(age ?? "")'")
    }

    @discardableResult
    public func addGroup(name: String, groupType: String, siteId: Int?, ageGroup: String? = nil,
                         notes: String? = nil) throws -> Int {
        let age = Self.blank(ageGroup)
        try validateGroup(name, groupType, siteId, age)
        do {
            return try db.run("INSERT INTO client_group(name,group_type,site_id,age_group,notes) VALUES(?,?,?,?,?)",
                              [Self.trim(name), groupType, siteId, age, Self.blank(notes)])
        } catch let e as DBError where e.isConstraint {
            throw ValidationError("Group '\(name)' already exists.")
        }
    }

    public func updateGroup(id: Int, name: String, groupType: String, siteId: Int?,
                            ageGroup: String? = nil, notes: String? = nil) throws {
        let age = Self.blank(ageGroup)
        try validateGroup(name, groupType, siteId, age)
        do {
            try db.run("UPDATE client_group SET name=?,group_type=?,site_id=?,age_group=?,notes=? WHERE id=?",
                       [Self.trim(name), groupType, siteId, age, Self.blank(notes), id])
        } catch let e as DBError where e.isConstraint {
            throw ValidationError("Group '\(name)' already exists.")
        }
    }

    public func closeGroup(id: Int, closedOn: String? = nil, note: String? = nil) throws {
        let closed = try Self.isoOrNil(closedOn) ?? Day.today()
        try db.transaction {
            try db.run("UPDATE client_group SET closed_on=?, closure_note=? WHERE id=?", [closed, Self.blank(note), id])
            try db.run("UPDATE slot SET active=0, end_date=? WHERE group_id=? AND active=1", [closed, id])
        }
    }

    public func reopenGroup(id: Int) throws {
        try db.run("UPDATE client_group SET closed_on=NULL, closure_note=NULL WHERE id=?", [id])
    }

    private static let groupSelect = """
        SELECT g.*, s.name AS site_name, s.degree_program AS degree,
        (SELECT COUNT(*) FROM entry e WHERE e.group_id=g.id AND e.planned=0) AS n_sessions,
        (SELECT COALESCE(SUM(minutes),0) FROM entry e WHERE e.group_id=g.id AND e.planned=0) AS minutes,
        (SELECT MAX(date) FROM entry e WHERE e.group_id=g.id AND e.planned=0) AS last_seen,
        (SELECT COUNT(*) FROM entry e WHERE e.group_id=g.id AND e.planned=1) AS n_planned
        FROM client_group g JOIN site s ON s.id=g.site_id
        """

    public func groups(openOnly: Bool = false) throws -> [ClientGroup] {
        try db.query(Self.groupSelect + (openOnly ? " WHERE g.closed_on IS NULL" : "")
                     + " ORDER BY g.name COLLATE NOCASE").map(ClientGroup.init)
    }

    public func group(_ id: Int) throws -> ClientGroup? {
        try db.one(Self.groupSelect + " WHERE g.id=?", [id]).map(ClientGroup.init)
    }

    // MARK: instruments

    public func instruments(activeOnly: Bool = false) throws -> [Instrument] {
        try db.query("SELECT * FROM instrument" + (activeOnly ? " WHERE active=1" : "")
                     + " ORDER BY name COLLATE NOCASE").map(Instrument.init)
    }

    @discardableResult
    public func addInstrument(_ name: String) throws -> Int {
        try Self.check(Self.blank(name) != nil, "Instrument name is required.")
        if let r = try db.one("SELECT id FROM instrument WHERE name=? COLLATE NOCASE", [Self.trim(name)]) {
            return r.int("id")!
        }
        return try db.run("INSERT INTO instrument(name) VALUES(?)", [Self.trim(name)])
    }

    public func updateInstrument(id: Int, name: String, active: Bool = true) throws {
        try Self.check(Self.blank(name) != nil, "Instrument name is required.")
        do {
            try db.run("UPDATE instrument SET name=?, active=? WHERE id=?", [Self.trim(name), active, id])
        } catch let e as DBError where e.isConstraint {
            throw ValidationError("An instrument with that name already exists.")
        }
    }

    // MARK: entries

    func validateEntry(_ e: EntryInput) throws {
        try Self.check(Vocab.activities(for: e.category).contains(e.activity),
                       "'\(e.activity)' is not a valid \(e.category.rawValue) activity.")
        try Self.check(e.minutes > 0, "Duration must be more than 0 minutes.")
        try Self.check(e.minutes <= 24 * 60, "Duration can't exceed 24 hours.")
        try Self.check(e.siteId != nil, "Site is required.")
        try Self.check(Vocab.modalities.contains(e.modality), "Unknown modality: '\(e.modality)'")
        try Self.check(Day.isValid(e.date), "Date is required.")
        try Self.check(!(e.clientId != nil && e.groupId != nil), "Pick a client or a group, not both.")

        switch e.category {
        case .intervention:
            if let gtype = Vocab.groupType(for: e.activity) {
                try Self.check(e.groupId != nil, "\(e.activity) must be logged to a \(gtype) group.")
                let row = try db.one("SELECT group_type FROM client_group WHERE id=?", [e.groupId])
                try Self.check(row?.str("group_type") == gtype,
                               "\(e.activity) must be logged to a group of type \(gtype).")
            } else {
                try Self.check(e.groupId == nil, "\(e.activity) is logged to an individual client, not a group.")
                if !Vocab.noClientOK.contains(e.activity) {
                    try Self.check(e.clientId != nil, "\(e.activity) needs a client.")
                }
            }
        case .assessment:
            try Self.check(e.clientId != nil, "Assessment sessions need a client.")
            try Self.check(e.purpose.map(Vocab.assessmentPurposes.contains) ?? false,
                           "Pick a purpose (Clinical or Research).")
        case .supervision:
            try Self.check(e.supervisorId != nil, "Supervision needs a supervisor.")
            try Self.check(e.clientId == nil && e.groupId == nil, "Supervision isn't logged to a client.")
        case .support:
            try Self.check(e.groupId == nil, "Support hours aren't logged to a group.")
        }
        if Vocab.needsSpecify(e.activity) {
            try Self.check(Self.blank(e.specify) != nil, "\(e.activity) needs a short description.")
        }
    }

    private func normalized(_ input: EntryInput) -> EntryInput {
        var e = input
        e.date = String(e.date.prefix(10))
        if e.category == .assessment {
            if e.purpose == nil { e.purpose = "Clinical" }
        } else {
            e.purpose = nil
            e.instrumentIds = []
        }
        if e.category != .supervision { e.supervisorId = nil }
        var seen = Set<Int>()
        e.instrumentIds = e.instrumentIds.filter { seen.insert($0).inserted }
        return e
    }

    @discardableResult
    public func addEntry(_ input: EntryInput) throws -> Int {
        let e = normalized(input)
        try validateEntry(e)
        return try db.transaction {
            let id = try db.run("INSERT INTO entry(date,site_id,category,activity,minutes,modality,client_id,group_id,supervisor_id,purpose,specify,note,slot_id,batch_id,planned) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                                [e.date, e.siteId, e.category.rawValue, e.activity, e.minutes, e.modality,
                                 e.clientId, e.groupId, e.supervisorId, e.purpose, Self.blank(e.specify),
                                 Self.blank(e.note), e.slotId, e.batchId, e.date > Day.today()])
            for i in e.instrumentIds {
                try db.run("INSERT INTO entry_instrument(entry_id,instrument_id) VALUES(?,?)", [id, i])
            }
            return id
        }
    }

    /// Insert many sessions atomically (batch add): all succeed or none do.
    /// They share a batch id so they can be found and edited together later.
    @discardableResult
    public func addEntriesBulk(_ inputs: [EntryInput]) throws -> [Int] {
        let batch = inputs.count > 1 ? UUID().uuidString : nil
        return try db.transaction {
            try inputs.enumerated().map { i, input in
                var e = input
                e.batchId = batch
                do { return try addEntry(e) } catch let err as ValidationError {
                    throw ValidationError("Session \(i + 1) (\(e.date)): \(err.message)")
                }
            }
        }
    }

    /// Dates on which this client/group already has an entry (to flag likely duplicates).
    public func loggedDates(clientId: Int? = nil, groupId: Int? = nil) throws -> Set<String> {
        if let clientId {
            return Set(try db.query("SELECT DISTINCT date FROM entry WHERE client_id=?", [clientId])
                .compactMap { $0.str("date") })
        }
        if let groupId {
            return Set(try db.query("SELECT DISTINCT date FROM entry WHERE group_id=?", [groupId])
                .compactMap { $0.str("date") })
        }
        return []
    }

    public func updateEntry(id: Int, _ input: EntryInput) throws {
        let e = normalized(input)
        try validateEntry(e)
        try db.transaction {
            try db.run("UPDATE entry SET date=?,site_id=?,category=?,activity=?,minutes=?,modality=?,client_id=?,group_id=?,supervisor_id=?,purpose=?,specify=?,note=?,planned=CASE WHEN ? THEN 1 WHEN ? IS NOT NULL THEN ? ELSE planned END,updated_at=datetime('now') WHERE id=?",
                       [e.date, e.siteId, e.category.rawValue, e.activity, e.minutes, e.modality, e.clientId,
                        e.groupId, e.supervisorId, e.purpose, Self.blank(e.specify), Self.blank(e.note),
                        e.date > Day.today(), e.planned, e.planned, id])
            try db.run("DELETE FROM entry_instrument WHERE entry_id=?", [id])
            for i in e.instrumentIds {
                try db.run("INSERT INTO entry_instrument(entry_id,instrument_id) VALUES(?,?)", [id, i])
            }
        }
    }

    public func deleteEntry(id: Int) throws {
        try db.run("DELETE FROM entry WHERE id=?", [id])
    }

    /// Change the same fields on many entries at once (atomic; every result is validated).
    public func updateEntries(ids: [Int], _ changes: EntryChanges) throws {
        try db.transaction {
            for id in ids {
                guard let e = try entry(id) else { continue }
                var input = EntryInput(entry: e, instrumentIds: try entryInstrumentIds(id))
                changes.apply(to: &input)
                do { try updateEntry(id: id, input) } catch let err as ValidationError {
                    throw ValidationError("\(Day.medium(e.date)) session: \(err.message)")
                }
            }
        }
    }

    /// Ids of every entry in the same batch.
    public func batchEntryIds(_ batchId: String) throws -> [Int] {
        try db.query("SELECT id FROM entry WHERE batch_id=? ORDER BY date", [batchId]).compactMap { $0.int("id") }
    }

    private static let entrySelect = """
        SELECT ef.*, (SELECT group_concat(i.name, ', ') FROM entry_instrument ei
        JOIN instrument i ON i.id=ei.instrument_id WHERE ei.entry_id=ef.id) AS instruments,
        (SELECT COUNT(*) FROM entry b WHERE b.batch_id = ef.batch_id) AS batch_size
        FROM entry_full ef
        """

    public func entry(_ id: Int) throws -> Entry? {
        try db.one(Self.entrySelect + " WHERE id=?", [id]).map(Entry.init)
    }

    public func entryInstrumentIds(_ entryId: Int) throws -> [Int] {
        try db.query("SELECT instrument_id FROM entry_instrument WHERE entry_id=?", [entryId])
            .compactMap { $0.int("instrument_id") }
    }

    public func entries(clientId: Int? = nil, groupId: Int? = nil, supervisorId: Int? = nil, since: String? = nil,
                        until: String? = nil, limit: Int? = nil) throws -> [Entry] {
        var wh: [String] = [], args: [Any?] = []
        if let clientId { wh.append("client_id=?"); args.append(clientId) }
        if let supervisorId { wh.append("supervisor_id=?"); args.append(supervisorId) }
        if let groupId { wh.append("group_id=?"); args.append(groupId) }
        if let since { wh.append("date>=?"); args.append(since) }
        if let until { wh.append("date<=?"); args.append(until) }
        var q = Self.entrySelect
        if !wh.isEmpty { q += " WHERE " + wh.joined(separator: " AND ") }
        q += " ORDER BY date DESC, id DESC"
        if let limit { q += " LIMIT \(limit)" }
        return try db.query(q, args).map(Entry.init)
    }

    public func lastEntry(clientId: Int? = nil, groupId: Int? = nil, supervisorId: Int? = nil) throws -> Entry? {
        let col: String, val: Int
        if let clientId { col = "client_id"; val = clientId }
        else if let groupId { col = "group_id"; val = groupId }
        else if let supervisorId { col = "supervisor_id"; val = supervisorId }
        else { return nil }
        return try db.one(Self.entrySelect + " WHERE \(col)=? ORDER BY date DESC, id DESC LIMIT 1", [val])
            .map(Entry.init)
    }

    /// Clients/groups ordered by most recently logged (for the quick-log picker).
    public func recentTargets(limit: Int = 200) throws -> [Who] {
        try db.query("""
            SELECT CASE WHEN client_id IS NOT NULL THEN 'client' ELSE 'group' END AS kind,
            COALESCE(client_id, group_id) AS tid, MAX(date || printf('%010d', id)) AS k
            FROM entry WHERE client_id IS NOT NULL OR group_id IS NOT NULL
            GROUP BY kind, tid ORDER BY k DESC LIMIT ?
            """, [limit]).compactMap { r in
            guard let tid = r.int("tid") else { return nil }
            return r.str("kind") == "client" ? .client(tid) : .group(tid)
        }
    }

    public func daysSinceLastEntry(today: String = Day.today()) -> Int? {
        guard let d = (try? db.one("SELECT MAX(date) AS d FROM entry WHERE planned=0"))?.str("d") else { return nil }
        return Day.between(d, today)
    }

    // MARK: planned (future) sessions

    /// Planned sessions whose date has arrived — waiting to be confirmed.
    public func duePlanned(today: String = Day.today()) throws -> [Entry] {
        try db.query(Self.entrySelect + " WHERE planned=1 AND date<=? ORDER BY date, id", [today]).map(Entry.init)
    }

    /// Planned sessions still in the future.
    public func upcomingPlannedCount(today: String = Day.today()) -> Int {
        ((try? db.scalar("SELECT COUNT(*) FROM entry WHERE planned=1 AND date>?", [today])) as? Int) ?? 0
    }

    /// It happened: count it. Only once its date has arrived.
    public func confirmPlanned(ids: [Int], today: String = Day.today()) throws {
        try db.transaction {
            for id in ids {
                try db.run("UPDATE entry SET planned=0, updated_at=datetime('now') WHERE id=? AND date<=?", [id, today])
            }
        }
    }

    /// Counted (non-planned) totals.
    public func totals() -> (count: Int, minutes: Int) {
        let r = try? db.one("SELECT COUNT(*) AS n, COALESCE(SUM(minutes),0) AS m FROM entry WHERE planned=0")
        return (r?.int("n") ?? 0, r?.int("m") ?? 0)
    }

    // MARK: reports

    @discardableResult
    public func addReport(clientId: Int?, date: String, reportType: String, purpose: String = "Clinical",
                          note: String? = nil, instrumentIds: [Int] = []) throws -> Int {
        try Self.check(clientId != nil, "Report needs a client.")
        try Self.check(Vocab.reportTypes.contains(reportType), "Unknown report type: '\(reportType)'")
        try Self.check(Vocab.assessmentPurposes.contains(purpose), "Unknown purpose: '\(purpose)'")
        let d = try Self.isoOrNil(date)
        try Self.check(d != nil, "Date is required.")
        return try db.transaction {
            let rid = try db.run("INSERT INTO report(client_id,date,report_type,purpose,note) VALUES(?,?,?,?,?)",
                                 [clientId, d, reportType, purpose, Self.blank(note)])
            var seen = Set<Int>()
            for i in instrumentIds where seen.insert(i).inserted {
                try db.run("INSERT INTO report_instrument(report_id,instrument_id) VALUES(?,?)", [rid, i])
            }
            return rid
        }
    }

    public func deleteReport(id: Int) throws { try db.run("DELETE FROM report WHERE id=?", [id]) }

    public func updateReport(id: Int, date: String, reportType: String, purpose: String = "Clinical",
                             note: String? = nil, instrumentIds: [Int] = []) throws {
        try Self.check(Vocab.reportTypes.contains(reportType), "Unknown report type: '\(reportType)'")
        try Self.check(Vocab.assessmentPurposes.contains(purpose), "Unknown purpose: '\(purpose)'")
        let d = try Self.isoOrNil(date)
        try Self.check(d != nil, "Date is required.")
        try db.transaction {
            try db.run("UPDATE report SET date=?, report_type=?, purpose=?, note=? WHERE id=?",
                       [d, reportType, purpose, Self.blank(note), id])
            try db.run("DELETE FROM report_instrument WHERE report_id=?", [id])
            var seen = Set<Int>()
            for i in instrumentIds where seen.insert(i).inserted {
                try db.run("INSERT INTO report_instrument(report_id,instrument_id) VALUES(?,?)", [id, i])
            }
        }
    }

    public func reportInstrumentIds(_ reportId: Int) throws -> [Int] {
        try db.query("SELECT instrument_id FROM report_instrument WHERE report_id=?", [reportId])
            .compactMap { $0.int("instrument_id") }
    }

    /// Date of the earliest counted session (for an "all time" chart range).
    public func firstEntryDate() -> String? {
        (try? db.one("SELECT MIN(date) AS d FROM entry WHERE planned=0"))?.str("d")
    }

    public func reports(clientId: Int? = nil) throws -> [Report] {
        var q = """
            SELECT r.*, c.code AS client_code, c.age_group, s.degree_program AS degree,
            (SELECT group_concat(i.name, ', ') FROM report_instrument ri
             JOIN instrument i ON i.id=ri.instrument_id WHERE ri.report_id=r.id) AS instruments
            FROM report r JOIN client c ON c.id=r.client_id JOIN site s ON s.id=c.site_id
            """
        var args: [Any?] = []
        if let clientId { q += " WHERE r.client_id=?"; args.append(clientId) }
        return try db.query(q + " ORDER BY r.date DESC", args).map(Report.init)
    }

    public func instrumentsUsed(clientId: Int) throws -> [Int] {
        try db.query("SELECT DISTINCT ei.instrument_id FROM entry_instrument ei JOIN entry e ON e.id=ei.entry_id WHERE e.client_id=?",
                     [clientId]).compactMap { $0.int("instrument_id") }
    }

    // MARK: recurring slots

    @discardableResult
    public func addSlot(weekday: Int, siteId: Int?, activity: String, minutes: Int,
                        category: HourCategory = .intervention, modality: String = Vocab.defaultModality,
                        clientId: Int? = nil, groupId: Int? = nil, supervisorId: Int? = nil,
                        time: String? = nil, startDate: String? = nil, endDate: String? = nil) throws -> Int {
        try Self.check((0...6).contains(weekday), "Weekday must be 0-6.")
        let start = try Self.isoOrNil(startDate) ?? Day.today()
        try validateEntry(EntryInput(date: start, siteId: siteId, category: category, activity: activity,
                                     minutes: minutes, modality: modality, clientId: clientId,
                                     groupId: groupId, supervisorId: supervisorId,
                                     purpose: category == .assessment ? "Clinical" : nil,
                                     specify: Vocab.needsSpecify(activity) ? "recurring" : nil))
        return try db.run("INSERT INTO slot(weekday,time,site_id,category,activity,minutes,modality,client_id,group_id,supervisor_id,start_date,end_date) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                          [weekday, Self.blank(time), siteId, category.rawValue, activity, minutes, modality,
                           clientId, groupId, supervisorId, start, try Self.isoOrNil(endDate)])
    }

    public func setSlotActive(id: Int, _ active: Bool, endDate: String? = nil) throws {
        try db.run("UPDATE slot SET active=?, end_date=COALESCE(?, end_date) WHERE id=?",
                   [active, try Self.isoOrNil(endDate), id])
    }

    public func deleteSlot(id: Int) throws { try db.run("DELETE FROM slot WHERE id=?", [id]) }

    public func slots(activeOnly: Bool = false) throws -> [Slot] {
        try db.query("""
            SELECT sl.*, s.name AS site_name, c.code AS client_code, g.name AS group_name,
            sv.name AS supervisor_name FROM slot sl JOIN site s ON s.id=sl.site_id
            LEFT JOIN client c ON c.id=sl.client_id LEFT JOIN client_group g ON g.id=sl.group_id
            LEFT JOIN supervisor sv ON sv.id=sl.supervisor_id
            """ + (activeOnly ? " WHERE sl.active=1" : "") + " ORDER BY sl.weekday, sl.time")
            .map(Slot.init)
    }

    /// Occurrences of active slots in [start, end] not yet logged or skipped.
    public func pendingSlotOccurrences(from start: String, to end: String) throws -> [SlotOccurrence] {
        var out: [SlotOccurrence] = []
        for sl in try slots(activeOnly: true) {
            let sStart = max(start, sl.startDate)
            let sEnd = sl.endDate.map { min(end, $0) } ?? end
            var d = Day.add(sStart, days: (sl.weekday - Day.weekday(sStart) + 7) % 7)
            while d <= sEnd {
                let logged = try db.one("SELECT 1 FROM entry WHERE slot_id=? AND date=?", [sl.id, d]) != nil
                    || (try loggedByHand(sl, on: d))
                let skipped = try db.one("SELECT 1 FROM slot_skip WHERE slot_id=? AND date=?", [sl.id, d]) != nil
                if !logged && !skipped { out.append(SlotOccurrence(slot: sl, date: d)) }
                d = Day.add(d, days: 7)
            }
        }
        return out.sorted { ($0.date, $0.slot.time ?? "") < ($1.date, $1.slot.time ?? "") }
    }

    /// A session logged by hand on the slot's date for the same client / group / supervisor (and type)
    /// covers that occurrence, so it isn't offered for confirmation (and counted) a second time.
    private func loggedByHand(_ sl: Slot, on date: String) throws -> Bool {
        var q = "SELECT 1 FROM entry WHERE date=? AND category=? AND client_id IS ? AND group_id IS ? AND supervisor_id IS ?"
        var args: [Any?] = [date, sl.category.rawValue, sl.clientId, sl.groupId, sl.supervisorId]
        if sl.clientId == nil && sl.groupId == nil && sl.supervisorId == nil { q += " AND activity=?"; args.append(sl.activity) }
        return try db.one(q, args) != nil
    }

    @discardableResult
    public func confirmSlot(id: Int, date: String, minutes: Int? = nil) throws -> Int {
        guard let r = try db.one("SELECT * FROM slot WHERE id=?", [id]) else {
            throw ValidationError("Recurring session not found.")
        }
        let activity = r.str("activity") ?? ""
        return try addEntry(EntryInput(
            date: date, siteId: r.int("site_id"),
            category: HourCategory(rawValue: r.str("category") ?? "") ?? .intervention,
            activity: activity, minutes: minutes ?? r.int("minutes") ?? 60,
            modality: r.str("modality") ?? Vocab.defaultModality, clientId: r.int("client_id"),
            groupId: r.int("group_id"), supervisorId: r.int("supervisor_id"),
            specify: Vocab.needsSpecify(activity) ? "recurring" : nil, slotId: id))
    }

    public func skipSlot(id: Int, date: String) throws {
        try db.run("INSERT OR IGNORE INTO slot_skip(slot_id,date) VALUES(?,?)", [id, date])
    }
}
