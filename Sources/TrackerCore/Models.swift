import Foundation

public struct Site: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var settingType: String
    public var degreeProgram: String
    public var startDate: String?
    public var endDate: String?
    public var notes: String?
    public var active: Bool

    init(_ r: Row) {
        id = r.int("id")!; name = r.str("name") ?? ""; settingType = r.str("setting_type") ?? ""
        degreeProgram = r.str("degree_program") ?? ""; startDate = r.str("start_date")
        endDate = r.str("end_date"); notes = r.str("notes"); active = r.bool("active")
    }
}

public struct Supervisor: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var supervisorType: String
    public var siteId: Int?
    public var siteName: String?
    public var active: Bool
    // supervision received from them (counted sessions only)
    public var nSessions = 0
    public var minutes = 0
    public var individualMinutes = 0
    public var groupMinutes = 0
    public var lastSeen: String?
    public var nPlanned = 0
    public var shortType: String { Vocab.supervisorTypeShort[supervisorType] ?? supervisorType }

    init(_ r: Row) {
        id = r.int("id")!; name = r.str("name") ?? ""; supervisorType = r.str("supervisor_type") ?? ""
        siteId = r.int("site_id"); siteName = r.str("site_name"); active = r.bool("active")
        nSessions = r.int("n_sessions") ?? 0; minutes = r.int("minutes") ?? 0
        individualMinutes = r.int("individual_minutes") ?? 0; groupMinutes = r.int("group_minutes") ?? 0
        lastSeen = r.str("last_seen"); nPlanned = r.int("n_planned") ?? 0
    }
}

public enum ClientKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case therapy, assessment
    public var id: String { rawValue }
    public var label: String { self == .therapy ? "Therapy" : "Assessment" }
}

public struct Client: Identifiable, Hashable, Sendable {
    public var id: Int
    public var code: String
    public var siteId: Int
    public var siteName: String
    public var degree: String
    public var ageGroup: String
    public var race: String?
    public var gender: String?
    public var orientation: String?
    public var notes: String?
    public var openedOn: String?
    public var closedOn: String?
    public var closureNote: String?
    public var disabilities: [String]
    public var nSessions: Int
    public var minutes: Int
    public var lastSeen: String?
    public var nPlanned: Int = 0
    /// Type picked when the client was added (used until they have sessions).
    public var designatedKind: ClientKind = .therapy
    /// Any therapy (intervention) session → therapy; only assessment sessions → assessment;
    /// no sessions yet → the designated type.
    public var kind: ClientKind = .therapy
    public var isClosed: Bool { closedOn != nil }

    init(_ r: Row) {
        nPlanned = r.int("n_planned") ?? 0
        designatedKind = ClientKind(rawValue: r.str("kind") ?? "") ?? .therapy
        kind = ClientKind(rawValue: r.str("effective_kind") ?? "") ?? designatedKind
        id = r.int("id")!; code = r.str("code") ?? ""; siteId = r.int("site_id") ?? 0
        siteName = r.str("site_name") ?? ""; degree = r.str("degree") ?? ""
        ageGroup = r.str("age_group") ?? ""; race = r.str("race"); gender = r.str("gender")
        orientation = r.str("orientation"); notes = r.str("notes"); openedOn = r.str("opened_on")
        closedOn = r.str("closed_on"); closureNote = r.str("closure_note")
        disabilities = (r.str("disabilities") ?? "").components(separatedBy: "; ").filter { !$0.isEmpty }
        nSessions = r.int("n_sessions") ?? 0; minutes = r.int("minutes") ?? 0
        lastSeen = r.str("last_seen")
    }
}

public struct ClientGroup: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var groupType: String
    public var siteId: Int
    public var siteName: String
    public var degree: String
    public var ageGroup: String?
    public var notes: String?
    public var closedOn: String?
    public var closureNote: String?
    public var nSessions: Int
    public var minutes: Int
    public var lastSeen: String?
    public var nPlanned: Int = 0
    public var isClosed: Bool { closedOn != nil }
    public var shortType: String {
        ["Group Therapy": "group", "Family Therapy": "family", "Couples Therapy": "couple"][groupType]
            ?? groupType
    }

    init(_ r: Row) {
        nPlanned = r.int("n_planned") ?? 0
        id = r.int("id")!; name = r.str("name") ?? ""; groupType = r.str("group_type") ?? ""
        siteId = r.int("site_id") ?? 0; siteName = r.str("site_name") ?? ""
        degree = r.str("degree") ?? ""; ageGroup = r.str("age_group"); notes = r.str("notes")
        closedOn = r.str("closed_on"); closureNote = r.str("closure_note")
        nSessions = r.int("n_sessions") ?? 0; minutes = r.int("minutes") ?? 0
        lastSeen = r.str("last_seen")
    }
}

public struct Instrument: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var active: Bool
    init(_ r: Row) { id = r.int("id")!; name = r.str("name") ?? ""; active = r.bool("active") }
}

/// A logged entry with everything derived (the `entry_full` view).
public struct Entry: Identifiable, Hashable, Sendable {
    public var id: Int
    public var date: String
    public var siteId: Int
    public var category: HourCategory
    public var activity: String
    public var minutes: Int
    public var modality: String
    public var clientId: Int?
    public var groupId: Int?
    public var supervisorId: Int?
    public var purpose: String?
    public var specify: String?
    public var note: String?
    public var slotId: Int?
    public var siteName: String
    public var settingType: String
    public var degree: String
    public var clientCode: String?
    public var groupName: String?
    public var groupType: String?
    public var ageGroup: String?
    public var supervisorName: String?
    public var supervisorType: String?
    public var instruments: String?
    public var batchId: String?
    public var batchSize: Int
    /// Dated in the future (or not yet confirmed) — doesn't count toward any totals.
    public var planned: Bool

    public var who: String { clientCode ?? groupName ?? supervisorName ?? "" }
    public var isBatched: Bool { batchId != nil && batchSize > 1 }
    public var hours: Double { Double(minutes) / 60 }

    public init(_ r: Row) {
        id = r.int("id")!; date = r.str("date") ?? ""; siteId = r.int("site_id") ?? 0
        category = HourCategory(rawValue: r.str("category") ?? "") ?? .intervention
        activity = r.str("activity") ?? ""; minutes = r.int("minutes") ?? 0
        modality = r.str("modality") ?? Vocab.defaultModality
        clientId = r.int("client_id"); groupId = r.int("group_id"); supervisorId = r.int("supervisor_id")
        purpose = r.str("purpose"); specify = r.str("specify"); note = r.str("note")
        slotId = r.int("slot_id"); siteName = r.str("site_name") ?? ""
        settingType = r.str("setting_type") ?? ""; degree = r.str("degree") ?? ""
        clientCode = r.str("client_code"); groupName = r.str("group_name")
        groupType = r.str("group_type"); ageGroup = r.str("age_group")
        supervisorName = r.str("supervisor_name"); supervisorType = r.str("supervisor_type")
        instruments = r.str("instruments")
        batchId = r.str("batch_id"); batchSize = r.int("batch_size") ?? 0
        planned = r.bool("planned")
    }
}

public struct Report: Identifiable, Hashable, Sendable {
    public var id: Int
    public var clientId: Int
    public var date: String
    public var reportType: String
    public var purpose: String
    public var note: String?
    public var clientCode: String
    public var ageGroup: String?
    public var degree: String
    public var instruments: String?

    init(_ r: Row) {
        id = r.int("id")!; clientId = r.int("client_id") ?? 0; date = r.str("date") ?? ""
        reportType = r.str("report_type") ?? ""; purpose = r.str("purpose") ?? "Clinical"
        note = r.str("note"); clientCode = r.str("client_code") ?? ""; ageGroup = r.str("age_group")
        degree = r.str("degree") ?? ""; instruments = r.str("instruments")
    }
}

public struct Slot: Identifiable, Hashable, Sendable {
    public var id: Int
    public var weekday: Int
    public var time: String?
    public var siteId: Int
    public var siteName: String
    public var category: HourCategory
    public var activity: String
    public var minutes: Int
    public var modality: String
    public var clientId: Int?
    public var groupId: Int?
    public var supervisorId: Int?
    public var clientCode: String?
    public var groupName: String?
    public var supervisorName: String?
    public var startDate: String
    public var endDate: String?
    public var active: Bool
    public var who: String { clientCode ?? groupName ?? supervisorName ?? "" }

    init(_ r: Row) {
        id = r.int("id")!; weekday = r.int("weekday") ?? 0; time = r.str("time")
        siteId = r.int("site_id") ?? 0; siteName = r.str("site_name") ?? ""
        category = HourCategory(rawValue: r.str("category") ?? "") ?? .intervention
        activity = r.str("activity") ?? ""; minutes = r.int("minutes") ?? 0
        modality = r.str("modality") ?? Vocab.defaultModality
        clientId = r.int("client_id"); groupId = r.int("group_id"); supervisorId = r.int("supervisor_id")
        clientCode = r.str("client_code"); groupName = r.str("group_name")
        supervisorName = r.str("supervisor_name"); startDate = r.str("start_date") ?? ""
        endDate = r.str("end_date"); active = r.bool("active")
    }
}

public struct SlotOccurrence: Identifiable, Hashable, Sendable {
    public var slot: Slot
    public var date: String
    public var id: String { "\(slot.id)@\(date)" }
}

/// A client or a group — the "who" of a session.
public enum Who: Hashable, Sendable {
    case client(Int)
    case group(Int)
    public var clientId: Int? { if case .client(let id) = self { return id }; return nil }
    public var groupId: Int? { if case .group(let id) = self { return id }; return nil }
}

/// Everything needed to create or update an entry.
public struct EntryInput: Equatable, Sendable {
    public var date: String
    public var siteId: Int?
    public var category: HourCategory
    public var activity: String
    public var minutes: Int
    public var modality: String = Vocab.defaultModality
    public var clientId: Int? = nil
    public var groupId: Int? = nil
    public var supervisorId: Int? = nil
    public var purpose: String? = nil
    public var specify: String? = nil
    public var note: String? = nil
    public var instrumentIds: [Int] = []
    public var slotId: Int? = nil
    public var batchId: String? = nil
    /// When set, an edit puts back this counted/planned state (used by Undo). A future date always means planned.
    public var planned: Bool? = nil

    public init(date: String, siteId: Int?, category: HourCategory, activity: String, minutes: Int,
                modality: String = Vocab.defaultModality, clientId: Int? = nil, groupId: Int? = nil,
                supervisorId: Int? = nil, purpose: String? = nil, specify: String? = nil,
                note: String? = nil, instrumentIds: [Int] = [], slotId: Int? = nil) {
        self.date = date; self.siteId = siteId; self.category = category; self.activity = activity
        self.minutes = minutes; self.modality = modality; self.clientId = clientId
        self.groupId = groupId; self.supervisorId = supervisorId; self.purpose = purpose
        self.specify = specify; self.note = note; self.instrumentIds = instrumentIds
        self.slotId = slotId
    }
}

public struct ClientInput: Equatable, Sendable {
    public var code: String
    public var siteId: Int?
    public var ageGroup: String
    public var race: String? = nil
    public var gender: String? = nil
    public var orientation: String? = nil
    public var disabilities: [String] = []
    public var notes: String? = nil
    public var openedOn: String? = nil
    public var kind: ClientKind = .therapy

    public init(code: String, siteId: Int?, ageGroup: String, race: String? = nil,
                gender: String? = nil, orientation: String? = nil, disabilities: [String] = [],
                notes: String? = nil, openedOn: String? = nil, kind: ClientKind = .therapy) {
        self.code = code; self.siteId = siteId; self.ageGroup = ageGroup; self.race = race
        self.gender = gender; self.orientation = orientation; self.disabilities = disabilities
        self.notes = notes; self.openedOn = openedOn; self.kind = kind
    }
}

public struct ValidationError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension EntryInput {
    /// The editable fields of an existing entry.
    public init(entry e: Entry, instrumentIds: [Int]) {
        self.init(date: e.date, siteId: e.siteId, category: e.category, activity: e.activity, minutes: e.minutes,
                  modality: e.modality, clientId: e.clientId, groupId: e.groupId, supervisorId: e.supervisorId,
                  purpose: e.purpose, specify: e.specify, note: e.note, instrumentIds: instrumentIds,
                  slotId: e.slotId)
        batchId = e.batchId
        planned = e.planned
    }
}

/// Fields to change on many entries at once. nil = leave as is.
public struct EntryChanges: Equatable, Sendable {
    public var activity: String?
    public var siteId: Int?
    public var minutes: Int?
    public var modality: String?
    public var purpose: String?
    public var who: Who??               // .some(nil) = no client
    public var note: String??           // .some(nil) = clear
    public var specify: String??
    public var shiftDays: Int?          // move every date by N days

    public init() {}
    public var isEmpty: Bool { self == EntryChanges() }

    public func apply(to input: inout EntryInput) {
        if let activity { input.activity = activity }
        if let siteId { input.siteId = siteId }
        if let minutes { input.minutes = minutes }
        if let modality { input.modality = modality }
        if let purpose { input.purpose = purpose }
        if let who { input.clientId = who?.clientId; input.groupId = who?.groupId }
        if let note { input.note = note }
        if let specify { input.specify = specify }
        if let shiftDays, shiftDays != 0 { input.date = Day.add(input.date, days: shiftDays) }
    }
}
