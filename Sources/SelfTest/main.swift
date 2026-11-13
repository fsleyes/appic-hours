// Core self-tests (the Command Line Tools ship without XCTest).
//   swift run SelfTest                      run all tests
//   swift run SelfTest export DB OUT ASOF   export a database 
import Foundation
import TrackerCore

var failures = 0, passes = 0
var currentTest = ""

func expect(_ cond: @autoclosure () throws -> Bool, _ msg: String = "", line: Int = #line) {
    do {
        if try cond() { passes += 1 } else { failures += 1; print("  ✗ [\(currentTest)] line \(line) \(msg)") }
    } catch { failures += 1; print("  ✗ [\(currentTest)] line \(line) threw \(error)") }
}

func expectThrows(_ body: () throws -> Void, _ msg: String = "", line: Int = #line) {
    do { try body(); failures += 1; print("  ✗ [\(currentTest)] line \(line) expected an error \(msg)") }
    catch { passes += 1 }
}

func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    do { try body() } catch { failures += 1; print("  ✗ [\(name)] threw \(error)") }
}

// MARK: fixtures

struct World {
    let repo: Repo
    let dSite, mSite, sup, a, b, old, m, never, grp, fam, wisc, scid: Int
}

func makeWorld() throws -> World {
    let repo = Repo(try Schema.open(":memory:"))
    let d = try repo.addSite(name: "Dept Clinic", settingType: "Department Clinic", degreeProgram: "Doctoral",
                             startDate: "2026-06-01")
    let mm = try repo.addSite(name: "Old MA Site", settingType: "Community Mental Health Center",
                              degreeProgram: "Terminal Masters")
    let sup = try repo.addSupervisor(name: "Dr. Example", supervisorType: "Licensed Psychologist", siteId: d)
    let a = try repo.addClient(ClientInput(code: "AA", siteId: d, ageGroup: "18-64 years old",
                                           race: "European Origin/White", gender: "Female",
                                           orientation: "Heterosexual",
                                           disabilities: ["Serious Mental Illness", "Learning/Cognitive Disability"]))
    let b = try repo.addClient(ClientInput(code: "BB", siteId: d, ageGroup: "13-17 years old",
                                           race: "Latino-a/Hispanic", gender: "Male"))
    let old = try repo.addClient(ClientInput(code: "CC", siteId: d, ageGroup: "65+ years old", gender: "Female"))
    let m = try repo.addClient(ClientInput(code: "MM", siteId: mm, ageGroup: "6-12 years old", gender: "Male"))
    let never = try repo.addClient(ClientInput(code: "ZZ", siteId: d, ageGroup: "18-64 years old", gender: "Male"))
    let grp = try repo.addGroup(name: "DBT Group", groupType: "Group Therapy", siteId: d, ageGroup: "18+ years old")
    let fam = try repo.addGroup(name: "Fam 1", groupType: "Family Therapy", siteId: d)
    let wisc = try repo.addInstrument("WISC-V")
    let scid = try repo.addInstrument("SCID-5")
    return World(repo: repo, dSite: d, mSite: mm, sup: sup, a: a, b: b, old: old, m: m, never: never,
                 grp: grp, fam: fam, wisc: wisc, scid: scid)
}

func E(_ date: String, _ site: Int, _ cat: HourCategory, _ act: String, _ min: Int, client: Int? = nil,
       group: Int? = nil, sup: Int? = nil, purpose: String? = nil, inst: [Int] = [],
       modality: String = "In person", specify: String? = nil) -> EntryInput {
    EntryInput(date: date, siteId: site, category: cat, activity: act, minutes: min, modality: modality,
               clientId: client, groupId: group, supervisorId: sup, purpose: purpose, specify: specify,
               instrumentIds: inst)
}

func logged() throws -> World {
    let w = try makeWorld(), r = w.repo, d = w.dSite
    for day in ["2026-09-01", "2026-09-08", "2026-09-15"] {
        try r.addEntry(E(day, d, .intervention, "Individual Therapy", 60, client: w.a))
    }
    try r.addEntry(E("2026-09-02", d, .intervention, "Individual Therapy", 45, client: w.b, modality: "Telehealth (video)"))
    try r.addEntry(E("2026-09-03", d, .intervention, "Career Counseling", 60, client: w.old))
    for day in ["2026-09-04", "2026-09-11"] {
        try r.addEntry(E(day, d, .intervention, "Group Counseling", 90, group: w.grp))
    }
    try r.addEntry(E("2026-09-05", d, .intervention, "Family Therapy", 60, group: w.fam))
    try r.addEntry(E("2026-09-06", w.mSite, .intervention, "Individual Therapy", 60, client: w.m))
    try r.addEntry(E("2026-09-07", d, .assessment, "Psychodiagnostic", 120, client: w.b, purpose: "Clinical", inst: [w.wisc]))
    try r.addEntry(E("2026-09-14", d, .assessment, "Psychodiagnostic", 60, client: w.b, purpose: "Clinical", inst: [w.wisc, w.scid]))
    try r.addEntry(E("2026-09-08", d, .assessment, "Psychodiagnostic", 60, client: w.a, purpose: "Research", inst: [w.scid]))
    try r.addReport(clientId: w.b, date: "2026-09-20", reportType: "Integrated Report", instrumentIds: [w.wisc, w.scid])
    try r.addEntry(E("2026-09-09", d, .supervision, "Individual Supervision", 60, sup: w.sup))
    try r.addEntry(E("2026-09-09", d, .support, "Clinical Writing/Progress Notes", 30))
    try r.addEntry(E("2026-11-01", d, .support, "Chart Review", 30))
    return w
}

func line(_ s: AAPI.Summary, _ section: String, _ label: String) -> AAPI.Line? {
    for sec in s.sections + [s.demographics] where sec.title.hasPrefix(section) {
        if let l = sec.lines.first(where: { $0.label == label }) { return l }
    }
    return nil
}

// MARK: export mode

let args = CommandLine.arguments
if args.count >= 4 && args[1] == "export" {
    let repo = Repo(try Schema.open(args[2]))
    try Export.workbook(repo, to: URL(fileURLWithPath: args[3]), asOf: args.count > 4 ? args[4] : Day.today())
    print("exported \(args[3])")
    exit(0)
}

// MARK: demo seed (fictional data for screenshots)

if args.count >= 3 && args[1] == "semesters" {          // print semesters for a database (opens + migrates it)
    for s in try Repo(try Schema.open(args[2])).semesters() {
        print("\(s.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(s.start) – \(s.end ?? "onward   ")  "
              + "\((s.supervisorName ?? "—").padding(toLength: 16, withPad: " ", startingAt: 0)) "
              + "\(s.sessions) sessions, \(AAPI.fmt(Double(s.minutes) / 60)) h")
    }
    exit(0)
}

if args.count >= 3 && args[1] == "seed" {
    let r = Repo(try Schema.open(args[2]))
    let today = Day.today()
    let d = try r.addSite(name: "University Training Clinic", settingType: "Department Clinic",
                          startDate: Day.add(today, days: -150))
    let cmhc = try r.addSite(name: "Riverside CMHC", settingType: "Community Mental Health Center",
                             startDate: Day.add(today, days: -60))
    let sup = try r.addSupervisor(name: "Dr. Rivera", supervisorType: Vocab.supervisorTypes[0], siteId: d)
    let sup2 = try r.addSupervisor(name: "Dr. Okafor", supervisorType: Vocab.supervisorTypes[0], siteId: cmhc)
    let specs: [(String, Int, String, String?, String?)] = [
        ("AB", d, "18-64 years old", "Female", "European Origin/White"),
        ("CJ", d, "18-64 years old", "Male", "African American/Black/African Origin"),
        ("DK", d, "13-17 years old", "Female", "Latino-a/Hispanic"),
        ("EM", cmhc, "18-64 years old", "Other", "Biracial/Multiracial"),
        ("FT", cmhc, "65+ years old", "Male", "Asian American/Asian Origin/Pacific Islander"),
        ("GR", d, "6-12 years old", "Male", nil),
        ("HS", cmhc, "18-64 years old", "Female", "European Origin/White"),
    ]
    var ids: [Int] = []
    for (code, site, age, g, race) in specs {
        ids.append(try r.addClient(ClientInput(code: code, siteId: site, ageGroup: age, race: race, gender: g)))
    }
    let grp = try r.addGroup(name: "DBT Skills Group", groupType: "Group Therapy", siteId: d, ageGroup: "18+ years old")
    let wisc = try r.addInstrument("WISC-V"), wais = try r.addInstrument("WAIS-IV")
    _ = try r.addInstrument("PAI"); _ = try r.addInstrument("SCID-5")
    for w in 0..<14 {
        let monday = Day.add(today, days: -Day.weekday(today) - 7 * w)
        for (i, cid) in ids.enumerated() where (w + i) % 5 != 0 && !(i == 4 && w < 3) {
            let date = Day.add(monday, days: i % 5)
            if date > today { continue }
            try r.addEntry(E(date, i == 3 || i == 4 || i == 6 ? cmhc : d, .intervention, "Individual Therapy",
                             i == 2 ? 45 : 50, client: cid, modality: i == 6 ? "Telehealth (video)" : "In person"))
        }

        let sd = Day.add(monday, days: 1)
        if sd <= today {
            try r.addEntry(E(sd, d, .supervision, "Individual Supervision", 60, sup: sup))
            try r.addEntry(E(sd, d, .support, "Clinical Writing/Progress Notes", 120))
            if w % 2 == 0 { try r.addEntry(E(Day.add(sd, days: 1), cmhc, .supervision, "Group Supervision", 90, sup: sup2)) }
        }
    }
    // the DBT group's 13 weekly sessions, batch-added in one go (like the real tracker)
    let thisThursday = Day.add(today, days: 3 - Day.weekday(today))
    let lastThursday = thisThursday <= today ? thisThursday : Day.add(thisThursday, days: -7)
    try r.addEntriesBulk((0..<13).map { E(Day.add(lastThursday, days: -7 * $0), d, .intervention, "Group Counseling", 90, group: grp) })
    try r.addEntry(E(Day.add(today, days: -40), d, .assessment, "Psychodiagnostic", 180, client: ids[5], purpose: "Clinical", inst: [wisc]))
    try r.addEntry(E(Day.add(today, days: -33), d, .assessment, "Psychodiagnostic", 120, client: ids[5], purpose: "Clinical", inst: [wisc]))
    try r.addEntry(E(Day.add(today, days: -20), d, .assessment, "Neuropsychological", 150, client: ids[1], purpose: "Clinical", inst: [wais]))
    try r.addReport(clientId: ids[5], date: Day.add(today, days: -25), reportType: "Integrated Report", instrumentIds: [wisc])
    try r.addSlot(weekday: Day.weekday(today), siteId: d, activity: "Individual Therapy", minutes: 50, clientId: ids[0],
                  startDate: Day.add(today, days: -15))
    try r.addSlot(weekday: (Day.weekday(today) + 6) % 7, siteId: d, activity: "Group Counseling", minutes: 90,
                  groupId: grp, startDate: Day.add(today, days: -10))
    try r.closeClient(id: ids[4], closedOn: Day.add(today, days: -21), note: "Goals met")
    // planned: 3 future sessions for AB, and one planned session whose date has now passed
    try r.addEntriesBulk([7, 14, 21].map { E(Day.add(today, days: $0), d, .intervention, "Individual Therapy", 50, client: ids[0]) })
    let due = try r.addEntry(E(Day.add(today, days: 5), cmhc, .intervention, "Intake Interview/Structured Interview", 90, client: ids[3]))
    try r.db.run("UPDATE entry SET date=? WHERE id=?", [Day.add(today, days: -2), due])
    let y = Day.year(today)
    try r.addSemesters([y - 1, y].flatMap { yr in ["Spring", "Summer", "Fall"].map { Repo.typicalTerm($0, yr) } })
    print("seeded \(args[2])")
    exit(0)
}

// MARK: tests

test("entry validation") {
    let w = try makeWorld(), r = w.repo
    expectThrows({ try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Individual Therapy", 60)) })
    expectThrows({ try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Group Counseling", 60, group: w.fam)) })
    expectThrows({ try r.addEntry(E("2026-09-01", w.dSite, .supervision, "Individual Supervision", 60)) })
    expectThrows({ try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Other Interventions (specify)", 60, client: w.a)) })
    expectThrows({ try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Not a thing", 60, client: w.a)) })
    let id = try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Program Development/Outreach Programming", 90))
    expect(try r.entry(id)?.degree == "Doctoral")
}

test("close client ends slots and hides") {
    let w = try makeWorld(), r = w.repo
    let sid = try r.addSlot(weekday: 0, siteId: w.dSite, activity: "Individual Therapy", minutes: 60,
                            clientId: w.a, startDate: "2026-09-01")
    expect(!(try r.pendingSlotOccurrences(from: "2026-09-01", to: "2026-09-30")).isEmpty)
    try r.closeClient(id: w.a, closedOn: "2026-09-10", note: "Terminated — goals met")
    let c = try r.client(w.a)!
    expect(c.closedOn == "2026-09-10" && (c.closureNote ?? "").hasPrefix("Terminated"))
    expect(!(try r.clients(openOnly: true)).contains { $0.id == w.a })
    expect(try r.pendingSlotOccurrences(from: "2026-09-01", to: "2026-09-30").isEmpty)
    try r.reopenClient(id: w.a)
    expect(try r.client(w.a)?.closedOn == nil)
    expect(try r.slots().first?.id == sid)
}

test("slots confirm and skip") {
    let w = try makeWorld(), r = w.repo
    let sid = try r.addSlot(weekday: 2, siteId: w.dSite, activity: "Individual Therapy", minutes: 50,
                            clientId: w.b, startDate: "2026-09-01")
    var occ = try r.pendingSlotOccurrences(from: "2026-09-01", to: "2026-09-21")
    expect(occ.map(\.date) == ["2026-09-02", "2026-09-09", "2026-09-16"], "\(occ.map(\.date))")
    try r.confirmSlot(id: sid, date: occ[0].date)
    try r.skipSlot(id: sid, date: occ[1].date)
    occ = try r.pendingSlotOccurrences(from: "2026-09-01", to: "2026-09-21")
    expect(occ.map(\.date) == ["2026-09-16"])
    let e = try r.entries(clientId: w.b).first!
    expect(e.minutes == 50 && e.slotId == sid)
}

test("backup rotation") {
    let w = try makeWorld()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString)")
    for i in 1...5 { try Schema.backup(w.repo.db, to: dir, keep: 3, today: "2026-01-0\(i)") }
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    expect(names == ["tracker-2026-01-03.db", "tracker-2026-01-04.db", "tracker-2026-01-05.db"], "\(names)")
    try? FileManager.default.removeItem(at: dir)
}

test("data dir must be outside app") {
    let app = URL(fileURLWithPath: "/tmp/fakeapp")
    expectThrows({ try AppConfig.validate(app.appendingPathComponent("data"), forbidden: [app]) })
    expectThrows({ try AppConfig.validate(app, forbidden: [app]) })
    expect((try? AppConfig.validate(URL(fileURLWithPath: "/tmp/elsewhere"), forbidden: [app])) != nil)
}

test("intervention rollup") {
    let w = try logged()
    let s = try AAPI.build(w.repo, asOf: "2026-10-01")
    let adults = line(s, "INTERVENTION", "18-64 years old")!
    expect(adults.cells["Doctoral"]?.hours == 3 && adults.cells["Doctoral"]?.count == 1)
    expect(line(s, "INTERVENTION", "13-17 years old")!.cells["Doctoral"]?.hours == 0.75)
    let kids = line(s, "INTERVENTION", "6-12 years old")!
    expect(kids.cells["Terminal Masters"]?.hours == 1 && kids.cells["Doctoral"]?.hours == 0)
    expect(kids.cells["Total"]?.count == 1)
    expect(line(s, "INTERVENTION", "Adults (18+)")!.cells["Total"]?.hours == 1)
    let grp = line(s, "INTERVENTION", "18+ years old")!
    expect(grp.cells["Doctoral"]?.hours == 3 && grp.cells["Doctoral"]?.count == 1)
    expect(line(s, "INTERVENTION", "Family Therapy (# families)")!.cells["Total"]?.count == 1)
    expect(line(s, "INTERVENTION", "TOTAL INTERVENTION")!.cells["Total"]?.hours == 9.75)
}

test("assessment, supervision, support") {
    let w = try logged()
    let s = try AAPI.build(w.repo, asOf: "2026-10-01")
    let psy = line(s, "ASSESSMENT", "Psychodiagnostic")!
    expect(psy.cells["Doctoral"]?.hours == 4 && psy.cells["Doctoral"]?.count == 2)
    expect(line(s, "ASSESSMENT", "Research")!.cells["Total"]?.hours == 1)
    let lines = s.sections.first { $0.title == "ASSESSMENT" }!.lines
    let i = lines.firstIndex { $0.label == "Integrated Psychological Reports (# reports)" }!
    expect(lines[i + 1].label == "Adults" && lines[i + 1].cells["Total"]?.count == 0)
    expect(lines[i + 2].cells["Doctoral"]?.count == 1)
    expect(line(s, "SUPERVISION", "Licensed Psychologist")!.cells["Doctoral"]?.hours == 1)
    expect(line(s, "SUPPORT", "TOTAL SUPPORT")!.cells["Total"]?.hours == 0.5)
    let h = s.instruments.headers
    let wisc = s.instruments.rows.first { $0[0] == .text("WISC-V") }!
    let scid = s.instruments.rows.first { $0[0] == .text("SCID-5") }!
    expect(wisc[h.firstIndex(of: "Clinical – Children/Adolescents")!] == .number(2))
    expect(scid[h.firstIndex(of: "Research – Adults")!] == .number(1))
    expect(scid[h.firstIndex(of: "Integrated reports using it")!] == .number(1))
    expect(line(s, "MODALITY", "Telehealth (video)")!.cells["Total"]?.hours == 0.75)
}

test("demographics only clients seen") {
    let w = try logged()
    let s = try AAPI.build(w.repo, asOf: "2026-10-01")
    let total = line(s, "CLIENT DEMOGRAPHICS", "Total clients seen")!
    expect(total.cells["Total"]?.count == 4 && total.cells["Terminal Masters"]?.count == 1)
    expect(line(s, "CLIENT DEMOGRAPHICS", "Serious Mental Illness")!.cells["Total"]?.count == 1)
    let male = line(s, "CLIENT DEMOGRAPHICS", "Male")!
    expect(male.cells["Doctoral"]?.count == 1 && male.cells["Terminal Masters"]?.count == 1)
}

test("settings and anticipated") {
    let w = try logged()
    try w.repo.setMeta("internship_start", "2027-07-01")
    let s = try AAPI.build(w.repo, asOf: "2026-10-01")
    expect(line(s, "TREATMENT SETTINGS", "Department Clinic")!.cells["Total"]?.hours == 12.75)
    expect(s.anticipated.internshipStart == "2027-07-01" && s.anticipated.weeksLeft > 30)
    let row = s.anticipated.table.rows[0]
    if case .number(let now) = row[1], case .number(let proj) = row[4] { expect(proj > now) } else { expect(false) }
}

test("export roundtrip") {
    let w = try logged()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString).xlsx")
    try Export.workbook(w.repo, to: url, asOf: "2026-10-01")
    let rows = try XLSXReader.rows(from: url)          // the importer reads the "Clients" sheet
    expect((rows.first?.first as? String) == "Client ID / Pseudonym", "\(rows.first ?? [])")
    expect(Set(rows.dropFirst().compactMap { $0.first as? String }) == ["AA", "BB", "CC", "MM", "ZZ"])
    try? FileManager.default.removeItem(at: url)
}

test("batch parse old tracker headers") {
    let w = try makeWorld()
    let text = "Client ID / Pseudonym\tClinical Setting\tClient Age\tRace / Ethnicity\tGender\tSexual Orientation\tHas Disability?\tDisability Type\tDegree (auto)\n"
        + "N1\tdept clinic\t18-64 years old\tAfrican American/Black/African Origin\tMale\t\tNo\t\tDoctoral\n"
        + "50031\tDept\t34\twhite\tf\tstraight\tYes\tSMI; learning\t\n"
        + "N3\tDept Clinic\tteen\tmixed\tnonbinary\tqueer\t\t\t\n"
    let rows = Batch.parseText(text, repo: w.repo)
    expect(rows.map(\.ok) == [true, true, true], "\(rows.map(\.errors))")
    let r2 = rows[1].values
    expect(r2["site"] == "Dept Clinic" && r2["age_group"] == "18-64 years old")
    expect(r2["race"] == "European Origin/White" && r2["gender"] == "Female" && r2["orientation"] == "Heterosexual")
    expect(rows[1].disabilities == ["Serious Mental Illness", "Learning/Cognitive Disability"])
    expect(rows[2].values["race"] == "Biracial/Multiracial")
    let ids = try w.repo.addClientsBulk(try Batch.toClientInputs(w.repo, rows))
    expect(ids.count == 3)
}

test("batch errors and atomicity") {
    let w = try makeWorld()
    let rows = Batch.parseRows([["X1", "Dept Clinic", "adult"], ["AA", "Dept Clinic", "adult"],
                                ["X1", "Dept Clinic", "adult"], ["X4", "Nowhere", "adult"], ["X5", "", "purple"]],
                               repo: w.repo, hasHeader: false)
    expect(rows[0].ok)
    expect(rows[1].errors["code"] != nil && (rows[2].errors["code"] ?? "").contains("row 1"))
    expect(rows[3].errors["site"] != nil)
    expect(rows[4].errors["site"] != nil && rows[4].errors["age_group"] != nil)
    expectThrows({ _ = try Batch.toClientInputs(w.repo, rows) })
    let r2 = Batch.parseRows([["Y1", "", "unknown"]], repo: w.repo, defaultSite: "Old MA Site", hasHeader: false)
    expect(r2[0].ok && r2[0].values["site"] == "Old MA Site")
    let before = try w.repo.clients().count
    expectThrows({
        try w.repo.addClientsBulk([ClientInput(code: "Q1", siteId: w.dSite, ageGroup: "18-64 years old"),
                                   ClientInput(code: "Q2", siteId: w.dSite, ageGroup: "bogus")])
    })
    expect(try w.repo.clients().count == before)
}

test("batch read xlsx and template") {
    let w = try makeWorld()
    // Build a workbook with our own writer, read it back through the importer.
    let wb = XWorkbook()
    let ws = wb.add("Clients")
    ws.append([.text("Client ID / Pseudonym"), .text("Clinical Setting"), .text("Client Age"), .text("Case Opened")])
    ws.append([.number(50058), .text("Dept Clinic"), .text("18-64 years old"), .date("2026-09-01")])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).xlsx")
    try wb.save(to: url)
    let rows = Batch.parseRows(try Batch.readFile(url), repo: w.repo)
    expect(rows.first?.ok == true && rows.first?.values["code"] == "50058", "\(rows.map(\.errors))")
    expect(rows.first?.values["opened_on"] == "2026-09-01", "\(rows.first?.values ?? [:])")
    let hdr = CSV.parse(Batch.templateCSV())[0]
    expect(Batch.looksLikeHeader(hdr))
    expect(Batch.mapHeaders(hdr).compactMap { $0 } == Batch.fieldNames)
    try? FileManager.default.removeItem(at: url)
}

test("batch add sessions") {
    let w = try makeWorld(), r = w.repo
    let parsed = Batch.parseDateList("9/2/2026\n2026-09-09; 9/16\nNov 6, 2026\nnot a date", defaultYear: 2026)
    expect(parsed.dates == ["2026-09-02", "2026-09-09", "2026-09-16", "2026-11-06"], "\(parsed.dates)")
    expect(parsed.bad == ["not a date"])
    expect(Batch.repeatingDates(start: "2026-09-01", count: 3) == ["2026-09-01", "2026-09-08", "2026-09-15"])
    let inputs = parsed.dates.map { E($0, w.dSite, .intervention, "Individual Therapy", 50, client: w.a) }
    let ids = try r.addEntriesBulk(inputs)
    expect(ids.count == 4)
    expect(try r.entries(clientId: w.a).count == 4)
    expect(try r.loggedDates(clientId: w.a).contains("2026-09-09"))
    // all-or-nothing
    var bad = inputs
    bad.append(E("2026-12-01", w.dSite, .intervention, "Individual Therapy", 0, client: w.a))
    expectThrows({ try r.addEntriesBulk(bad) })
    expect(try r.entries(clientId: w.a).count == 4)
}

test("delete client and group") {
    let w = try logged(), r = w.repo
    try r.addSlot(weekday: 1, siteId: w.dSite, activity: "Individual Therapy", minutes: 50, clientId: w.b,
                  startDate: "2026-09-01")
    let impact = try r.deletionImpact(clientId: w.b)
    expect(impact.sessions == 3 && impact.minutes == 225 && impact.reports == 1, "\(impact)")
    try r.deleteClient(id: w.b)
    expect(try r.client(w.b) == nil)
    expect(try r.entries(clientId: w.b).isEmpty && (try r.reports(clientId: w.b)).isEmpty)
    expect(try r.slots().isEmpty)
    expect(try r.db.scalar("SELECT COUNT(*) FROM entry_instrument ei LEFT JOIN entry e ON e.id=ei.entry_id WHERE e.id IS NULL") as? Int == 0)
    let s = try AAPI.build(r, asOf: "2026-10-01")
    expect(line(s, "INTERVENTION", "13-17 years old")!.cells["Total"]?.hours == 0)
    try r.deleteGroup(id: w.grp)
    expect(try r.group(w.grp) == nil && (try r.entries(groupId: w.grp)).isEmpty)
    expect(try r.client(w.a) != nil)   // others untouched
}

test("batch ids and bulk edit") {
    let w = try makeWorld(), r = w.repo
    let dates = Batch.repeatingDates(start: "2026-08-06", count: 13)
    let ids = try r.addEntriesBulk(dates.map { E($0, w.dSite, .intervention, "Group Counseling", 90, group: w.grp) })
    let single = try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Individual Therapy", 50, client: w.a))
    let es = try r.entries(groupId: w.grp)
    let bid = es[0].batchId
    expect(bid != nil && es.allSatisfy { $0.batchId == bid && $0.batchSize == 13 && $0.isBatched })
    expect(try r.entry(single)?.isBatched == false)
    expect(try r.batchEntryIds(bid!).sorted() == ids.sorted())
    // 1.5 h → 2 h for the whole batch
    var ch = EntryChanges(); ch.minutes = 120
    try r.updateEntries(ids: ids, ch)
    expect(try r.entries(groupId: w.grp).allSatisfy { $0.minutes == 120 })
    expect(try r.entry(single)?.minutes == 50)                       // untouched
    // other fields + date shift + note
    ch = EntryChanges(); ch.modality = "Telehealth (video)"; ch.note = .some("co-led"); ch.shiftDays = 1
    try r.updateEntries(ids: Array(ids.prefix(2)), ch)
    let first = try r.entry(ids[0])!
    expect(first.modality == "Telehealth (video)" && first.note == "co-led" && first.date == "2026-08-07")
    expect(first.batchId == bid)                                     // stays in the batch
    // invalid change → nothing changes (atomic)
    ch = EntryChanges(); ch.who = .some(.client(w.a))                // group service can't go to a client
    expectThrows({ try r.updateEntries(ids: ids, ch) })
    expect(try r.entries(groupId: w.grp).count == 13)
}

test("v2 migration backfills old batches") {
    let db = try Database(path: ":memory:")
    try db.exec("PRAGMA foreign_keys = ON")
    try db.exec(Schema.v1)
    try db.exec("PRAGMA user_version = 1")
    try db.run("INSERT INTO site(name,setting_type,degree_program) VALUES('S','School','Doctoral')")
    try db.run("INSERT INTO client_group(name,group_type,site_id) VALUES('G','Group Therapy',1)")
    try db.run("INSERT INTO client(code,site_id,age_group) VALUES('C',1,'18-64 years old')")
    for d in ["2026-08-06", "2026-08-13", "2026-08-20"] {   // batch-added: same second
        try db.run("INSERT INTO entry(date,site_id,category,activity,minutes,group_id,created_at) VALUES(?,1,'intervention','Group Counseling',90,1,'2026-11-06 15:00:00')", [d])
    }
    try db.run("INSERT INTO entry(date,site_id,category,activity,minutes,client_id,created_at) VALUES('2026-08-06',1,'intervention','Individual Therapy',50,1,'2026-11-06 15:00:00')")
    try db.run("INSERT INTO entry(date,site_id,category,activity,minutes,client_id,created_at) VALUES('2026-08-13',1,'intervention','Individual Therapy',50,1,'2026-11-06 15:05:00')")
    try Schema.migrate(db)
    expect(try db.scalar("PRAGMA user_version") as? Int == Schema.migrations.count)
    let r = Repo(db)
    let g = try r.entries(groupId: 1)
    expect(g.count == 3 && g.allSatisfy { $0.isBatched && $0.batchSize == 3 }, "\(g.map(\.batchId))")
    expect(try r.entries(clientId: 1).allSatisfy { !$0.isBatched })
    expect(try AAPI.build(r, asOf: "2026-12-01").totals["intervention"] == 6.5)    // view still works (50 min → 1 h)
}

test("backup before upgrade") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upg-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("tracker.db").path
    do {
        let db = try Database(path: path)
        try db.exec(Schema.v1)
        try db.exec("PRAGMA user_version = 1")
    }
    let copy = try Schema.backupBeforeUpgrade(dbPath: path, backupDir: dir.appendingPathComponent("backups"))
    expect(copy != nil && FileManager.default.fileExists(atPath: copy!.path))
    let old = try Database(path: copy!.path)
    expect(try old.scalar("PRAGMA user_version") as? Int == 1)            // untouched v1 copy
    _ = try Schema.open(path)                                              // upgrade
    expect(try Schema.backupBeforeUpgrade(dbPath: path, backupDir: dir) == nil)   // nothing to do now
    try? FileManager.default.removeItem(at: dir)
}

test("planned future sessions") {
    let w = try makeWorld(), r = w.repo
    let today = Day.today(), past = Day.add(today, days: -3), future = Day.add(today, days: 10)
    try r.addEntry(E(past, w.dSite, .intervention, "Individual Therapy", 60, client: w.a))
    let fut = try r.addEntry(E(future, w.dSite, .intervention, "Individual Therapy", 60, client: w.a))
    expect(try r.entry(fut)?.planned == true)
    expect(r.totals().minutes == 60)                                       // future one excluded
    let farAsOf = Day.add(today, days: 60)
    expect(try AAPI.build(r, asOf: farAsOf).totals["intervention"] == 1)  // even with a far as-of date
    let c = try r.client(w.a)!
    expect(c.nSessions == 1 && c.minutes == 60 && c.nPlanned == 1 && c.lastSeen == past)
    expect(try r.duePlanned().isEmpty && r.upcomingPlannedCount() == 1)
    // the day arrives → it's due; confirming early does nothing
    try r.confirmPlanned(ids: [fut], today: Day.add(future, days: -1))
    expect(try r.entry(fut)?.planned == true)
    expect(try r.duePlanned(today: future).map(\.id) == [fut])
    try r.confirmPlanned(ids: [fut], today: future)
    expect(try r.entry(fut)?.planned == false && r.totals().minutes == 120)
    // moving a counted session into the future makes it planned again
    var input = EntryInput(entry: try r.entry(fut)!, instrumentIds: [])
    input.date = Day.add(today, days: 5)
    try r.updateEntry(id: fut, input)
    expect(try r.entry(fut)?.planned == true && r.totals().minutes == 60)
    // batch with past + future dates: only the future ones are planned
    let ids = try r.addEntriesBulk([past, today, future].map { E($0, w.dSite, .intervention, "Individual Therapy", 50, client: w.b) })
    expect(try ids.map { try r.entry($0)!.planned } == [false, false, true])
    // export leaves planned sessions out
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("p-\(UUID().uuidString).xlsx")
    try Export.workbook(r, to: url, asOf: farAsOf)
    try? FileManager.default.removeItem(at: url)
}

test("v3 migration marks sessions entered ahead of time") {
    let db = try Database(path: ":memory:")
    try db.exec("PRAGMA foreign_keys = ON")
    try db.exec(Schema.v1); try db.exec(Schema.v2); try db.exec("PRAGMA user_version = 2")
    try db.run("INSERT INTO site(name,setting_type,degree_program) VALUES('S','School','Doctoral')")
    try db.run("INSERT INTO client(code,site_id,age_group) VALUES('C',1,'18-64 years old')")
    try db.run("INSERT INTO entry(date,site_id,category,activity,minutes,client_id,created_at) VALUES('2026-09-01',1,'intervention','Individual Therapy',50,1,'2026-09-02 15:00:00')")
    try db.run("INSERT INTO entry(date,site_id,category,activity,minutes,client_id,created_at) VALUES('2026-12-01',1,'intervention','Individual Therapy',50,1,'2026-11-06 15:00:00')")
    try Schema.migrate(db)
    let es = try Repo(db).entries(clientId: 1)
    expect(es.first { $0.date == "2026-12-01" }?.planned == true)
    expect(es.first { $0.date == "2026-09-01" }?.planned == false)
}

test("report editing") {
    let w = try logged(), r = w.repo
    let rep = try r.reports(clientId: w.b).first!
    try r.updateReport(id: rep.id, date: "2026-09-25", reportType: "Standard Report", purpose: "Research",
                       note: "revised", instrumentIds: [w.wisc])
    let e = try r.reports(clientId: w.b).first!
    expect(e.date == "2026-09-25" && e.reportType == "Standard Report" && e.purpose == "Research" && e.note == "revised")
    expect(try r.reportInstrumentIds(rep.id) == [w.wisc])
    expectThrows({ try r.updateReport(id: rep.id, date: "", reportType: "Standard Report") })
    let s = try AAPI.build(r, asOf: "2026-10-01")
    let lines = s.sections.first { $0.title == "ASSESSMENT" }!.lines
    let i = lines.firstIndex { $0.label == "Integrated Psychological Reports (# reports)" }!
    expect(lines[i + 2].cells["Total"]?.count == 0)                      // no longer integrated
}

test("weekly range and running average") {
    let w = try makeWorld(), r = w.repo
    // Mon 2026-09-07 .. Sun 2026-09-27 = 3 weeks: 2 h, 0 h, 4 h of intervention
    try r.addEntry(E("2026-09-08", w.dSite, .intervention, "Individual Therapy", 120, client: w.a))
    try r.addEntry(E("2026-09-22", w.dSite, .intervention, "Individual Therapy", 240, client: w.a))
    try r.addEntry(E("2026-09-22", w.dSite, .support, "Chart Review", 600))      // not intervention
    let pts = try AAPI.weekly(r, from: "2026-09-07", to: "2026-09-27")
    expect(Set(pts.map(\.weekStart)) == ["2026-09-07", "2026-09-14", "2026-09-21"])
    let (run, overall) = AAPI.runningAverage(pts, categories: [.intervention], from: "2026-09-07", to: "2026-09-27")
    expect(run.map(\.average) == [2, 1, 2], "\(run.map(\.average))")
    expect(overall == 2)
    // direct = intervention + assessment; support never included
    let (_, both) = AAPI.runningAverage(pts, categories: [.intervention, .assessment], from: "2026-09-07", to: "2026-09-27")
    expect(both == 2)
    expect(r.firstEntryDate() == "2026-09-08")
}

test("goal projections") {
    let w = try makeWorld(), r = w.repo
    // 2 h of intervention every Wednesday, Aug 5 → Sep 30 (9 sessions = 18 h)
    for d in Batch.repeatingDates(start: "2026-08-05", count: 9) {
        try r.addEntry(E(d, w.dSite, .intervention, "Individual Therapy", 120, client: w.a))
    }
    try r.addEntry(E("2026-09-30", w.dSite, .supervision, "Individual Supervision", 60, sup: w.sup))
    let p = try Goals.projection(r, metric: .intervention, goal: 30, deadline: "2026-11-01",
                                 asOf: "2026-09-30", paceWeeks: 8)
    expect(p.current == 18 && p.remaining == 12)
    expect(p.pacePerWeek == 2, "pace \(p.pacePerWeek)")                   // 16 h over the last 8 weeks
    expect(p.weeksLeft == 4.6)                                            // 32 days
    expect(p.neededPerWeek == 2.63, "needed \(String(describing: p.neededPerWeek))")
    expect(p.projected == 27.14 && !p.onTrack && abs(p.shortfall - 2.86) < 0.01)
    expect(p.projectedHitDate == "2026-11-11")
    expect(p.points.contains { $0.kind == .needed && $0.date == "2026-11-01" && $0.hours == 30 })
    expect(p.points.filter { $0.kind == .actual }.last?.hours == 18)
    let easy = try Goals.projection(r, metric: .intervention, goal: 25, deadline: "2026-11-01", asOf: "2026-09-30")
    expect(easy.onTrack && !easy.isMet)
    let met = try Goals.projection(r, metric: .intervention, goal: 10, deadline: "2026-11-01", asOf: "2026-09-30")
    expect(met.isMet && met.remaining == 0 && met.neededPerWeek == nil && met.progress == 1)
    // direct/total metrics pick the right categories
    expect(try Goals.projection(r, metric: .total, goal: 100, deadline: "2026-11-01", asOf: "2026-09-30").current == 19)
    expect(try Goals.projection(r, metric: .direct, goal: 100, deadline: "2026-11-01", asOf: "2026-09-30").current == 18)
    // deadline passed → nothing needed per week, projection = current
    let late = try Goals.projection(r, metric: .intervention, goal: 30, deadline: "2026-09-01", asOf: "2026-09-30")
    expect(late.weeksLeft == 0 && late.neededPerWeek == nil && late.projected == 18)
    // settings
    expect(Goals.deadline(r, today: "2026-10-01") == "2026-11-01")
    expect(Goals.deadline(r, today: "2026-11-02") == "2027-11-01")
    try Goals.setDeadline(r, "2026-11-15")
    try Goals.setGoal(r, .intervention, 300)
    try Goals.setGoal(r, .direct, 400)
    try Goals.setGoal(r, .direct, nil)                                     // cleared
    expect(Goals.deadline(r) == "2026-11-15" && Goals.goal(r, .intervention) == 300 && Goals.goal(r, .direct) == nil)
    expect(try Goals.all(r, asOf: "2026-09-30").map(\.metric) == [.intervention])
    expectThrows({ try Goals.setGoal(r, .total, -5) })
    // planned future sessions are reported separately, not counted
    let today = Day.today()
    try r.addEntry(E(Day.add(today, days: 10), w.dSite, .intervention, "Individual Therapy", 90, client: w.a))
    let pl = try Goals.projection(r, metric: .intervention, goal: 30, deadline: Day.add(today, days: 30), asOf: today)
    expect(pl.plannedBeforeDeadline == 1.5 && pl.current == 18)
}

test("client type: therapy vs assessment") {
    let w = try makeWorld(), r = w.repo
    let newT = try r.addClient(ClientInput(code: "NT", siteId: w.dSite, ageGroup: "18-64 years old"))
    let newA = try r.addClient(ClientInput(code: "NA", siteId: w.dSite, ageGroup: "6-12 years old", kind: .assessment))
    expect(try r.client(newT)?.kind == .therapy && r.client(newA)?.kind == .assessment)    // no sessions: as designated
    // designated therapy, but only assessment sessions so far → assessment
    try r.addEntry(E("2026-09-01", w.dSite, .assessment, "Psychodiagnostic", 120, client: newT, purpose: "Clinical"))
    expect(try r.client(newT)?.kind == .assessment && r.client(newT)?.designatedKind == .therapy)
    // any therapy (intervention) session → therapy, even if designated assessment
    try r.addEntry(E("2026-09-08", w.dSite, .intervention, "Individual Therapy", 50, client: newA))
    expect(try r.client(newA)?.kind == .therapy)
    // a planned future therapy session also makes them a therapy client
    let fut = try r.addClient(ClientInput(code: "FU", siteId: w.dSite, ageGroup: "18-64 years old", kind: .assessment))
    try r.addEntry(E(Day.add(Day.today(), days: 7), w.dSite, .intervention, "Individual Therapy", 50, client: fut))
    expect(try r.client(fut)?.kind == .therapy)
    // editing keeps / changes the designation
    var ci = ClientInput(code: "NT", siteId: w.dSite, ageGroup: "18-64 years old", kind: .assessment)
    try r.updateClient(id: newT, ci)
    expect(try r.client(newT)?.designatedKind == .assessment)
    ci.kind = .therapy
    _ = ci
    // batch: type column in a file, or the sheet default
    let rows = Batch.parseRows([["Client ID", "Clinical Setting", "Client Age", "Type"],
                                ["B1", "Dept Clinic", "adult", "assessment"],
                                ["B2", "Dept Clinic", "adult", "Therapy"],
                                ["B3", "Dept Clinic", "adult", ""],
                                ["B4", "Dept Clinic", "adult", "purple"]], repo: r, defaultKind: .assessment)
    expect(rows.map { $0.values["kind"] } == ["assessment", "therapy", "assessment", "assessment"], "\(rows.map { $0.values["kind"] })")
    expect(rows[3].errors["code"]?.contains("client type") == true)
    let ids = try r.addClientsBulk(try Batch.toClientInputs(r, Array(rows.prefix(3))))
    expect(try ids.map { try r.client($0)!.kind } == [.assessment, .therapy, .assessment])
    expect(Batch.parseKind("Testing") == .assessment && Batch.parseKind("tx") == .therapy && Batch.parseKind("x") == nil)
}

test("v4 migration sets type from sessions") {
    let db = try Database(path: ":memory:")
    try db.exec("PRAGMA foreign_keys = ON")
    try db.exec(Schema.v1); try db.exec(Schema.v2); try db.exec(Schema.v3); try db.exec("PRAGMA user_version = 3")
    try db.run("INSERT INTO site(name,setting_type,degree_program) VALUES('S','School','Doctoral')")
    for code in ["T", "A", "N"] { try db.run("INSERT INTO client(code,site_id,age_group) VALUES(?,1,'18-64 years old')", [code]) }
    try db.run("INSERT INTO entry(date,site_id,category,activity,minutes,client_id) VALUES('2026-09-01',1,'intervention','Individual Therapy',50,1)")
    try db.run("INSERT INTO entry(date,site_id,category,activity,minutes,client_id,purpose) VALUES('2026-09-01',1,'assessment','Psychodiagnostic',120,2,'Clinical')")
    try Schema.migrate(db)
    let cs = try Repo(db).clients()
    expect(cs.map(\.code) == ["A", "N", "T"])
    expect(cs.map(\.kind) == [.assessment, .therapy, .therapy] && cs[0].designatedKind == .assessment)
}

test("supervisor stats and sessions") {
    let w = try makeWorld(), r = w.repo
    let other = try r.addSupervisor(name: "Dr. Two", supervisorType: Vocab.supervisorTypes[1], siteId: w.dSite)
    try r.addEntry(E("2026-09-01", w.dSite, .supervision, "Individual Supervision", 60, sup: w.sup))
    try r.addEntry(E("2026-09-08", w.dSite, .supervision, "Group Supervision", 90, sup: w.sup))
    try r.addEntry(E("2026-09-09", w.dSite, .supervision, "Individual Supervision", 30, sup: other))
    try r.addEntry(E(Day.add(Day.today(), days: 7), w.dSite, .supervision, "Individual Supervision", 60, sup: w.sup))
    let s1 = try r.supervisors().first { $0.id == w.sup }!
    expect(s1.nSessions == 2 && s1.minutes == 150 && s1.individualMinutes == 60 && s1.groupMinutes == 90)
    expect(s1.lastSeen == "2026-09-08" && s1.nPlanned == 1)
    expect(try r.entries(supervisorId: w.sup).count == 3)                 // incl. the planned one
    expect(try r.entries(supervisorId: other).map(\.minutes) == [30])
}

test("batch clients: closed column") {
    let w = try makeWorld(), r = w.repo
    let rows = Batch.parseRows([["Client ID", "Clinical Setting", "Client Age", "Closed"],
                                ["K1", "Dept Clinic", "adult", "2026-05-30"],
                                ["K2", "Dept Clinic", "adult", "yes"],
                                ["K3", "Dept Clinic", "adult", "no"],
                                ["K4", "Dept Clinic", "adult", ""],
                                ["K5", "Dept Clinic", "adult", "maybe"]], repo: r)
    expect(rows[0].values["closed"] == "1" && rows[0].values["closed_on"] == "2026-05-30")
    expect(rows[1].values["closed"] == "1" && rows[1].values["closed_on"] == nil)
    expect(rows[2].values["closed"] == nil && rows[3].values["closed"] == nil)
    expect(rows[4].errors["code"]?.contains("closed") == true)
}

test("csv parser") {
    let rows = CSV.parse("a,\"b,c\",\"he said \"\"hi\"\"\"\n1,2,3\n")
    expect(rows == [["a", "b,c", "he said \"hi\""], ["1", "2", "3"]], "\(rows)")
}

test("weekly recap") {
    expect(WeekRecap.lastCompletedFriday(today: "2026-11-07") == "2026-11-06")   // Saturday
    expect(WeekRecap.lastCompletedFriday(today: "2026-11-09") == "2026-11-06")   // Monday
    expect(WeekRecap.lastCompletedFriday(today: "2026-11-13") == "2026-11-06")   // Friday: not over yet
    expect(WeekRecap.milestones(2900, 3100, stepHours: 50) == [50])
    expect(WeekRecap.milestones(0, 6000, stepHours: 50) == [50, 100])
    expect(WeekRecap.milestones(3000, 3060, stepHours: 50) == [])
    let w = try makeWorld(), r = w.repo
    try r.addEntry(E("2026-10-20", w.dSite, .intervention, "Individual Therapy", 600, client: w.a))   // earlier week
    try r.addEntry(E("2026-10-31", w.dSite, .intervention, "Individual Therapy", 60, client: w.a))    // Sat, in week
    try r.addEntry(E("2026-11-03", w.dSite, .assessment, "Psychodiagnostic", 120, client: w.b, inst: [w.scid]))
    try r.addEntry(E("2026-11-03", w.dSite, .supervision, "Individual Supervision", 60, sup: w.sup))
    try r.addEntry(E("2026-11-06", w.dSite, .intervention, "Group Counseling", 90, group: w.grp))
    try r.addEntry(E("2026-11-07", w.dSite, .support, "Clinical Writing/Progress Notes", 30))           // next week
    let x = try r.weekRecap(friday: "2026-11-06")
    expect(x.start == "2026-10-31" && x.days.count == 7 && x.days.last == "2026-11-06")
    expect(x.minutes == 330 && x.sessions == 4, "\(x.minutes) \(x.sessions)")
    expect(x.byCategory[.intervention] == 150 && x.byCategory[.assessment] == 120 && x.byCategory[.supervision] == 60)
    expect(x.byDay["2026-11-03"] == 180 && x.byDay["2026-11-01"] == 0)
    expect(x.people == 3 && x.newPeople == ["BB", "DBT Group"], "\(x.newPeople)")
    expect(x.instruments.map(\.name) == ["SCID-5"] && x.instruments.first?.count == 1)
    expect(x.totalBefore == 600 && x.totalAfter == 930 && x.directBefore == 600 && x.directAfter == 870)
    expect(x.averageMinutes == 600 / 2, "\(String(describing: x.averageMinutes))")   // history began 2 weeks earlier
    expect(r.firstRecapFriday() == "2026-10-23")
    expect(try r.weekRecap(friday: "2026-10-16").isEmpty)
}

test("semesters") {
    let w = try makeWorld(), r = w.repo
    expect(try r.semesters().isEmpty)                                    // new databases start with none
    expect(r.suggestedNextSemester(today: "2026-11-12") == ("Fall 2026", "2026-08-24"))
    expect(r.suggestedNextSemester(today: "2026-03-01") == ("Spring 2026", "2026-01-12"))
    expect(r.suggestedNextSemester(today: "2026-06-01") == ("Summer 2026", "2026-05-13"))
    expect(try r.addSemesters(SemesterPreset.temple.semesters) == 9)
    expect(try r.addSemesters(SemesterPreset.temple.semesters) == 0)     // presets don't duplicate
    var sems = try r.semesters()
    expect(sems.count == 9 && sems.first?.name == "Fall 2024" && sems.first?.end == "2025-01-12")
    expect(sems.last?.name == "Summer 2027" && sems.last?.end == nil)
    let summer = try r.addSupervisor(name: "Dr. Summer", supervisorType: Vocab.supervisorTypes[0], siteId: w.dSite)
    let fall = try r.addSupervisor(name: "Dr. Fall", supervisorType: Vocab.supervisorTypes[0], siteId: w.dSite)
    for d in ["2025-06-05", "2025-07-10", "2025-07-31", "2025-08-07", "2025-08-14"] {
        try r.addEntry(E(d, w.dSite, .supervision, "Group Supervision", 60, sup: summer))
    }
    for d in ["2025-08-07", "2025-08-14", "2025-09-04", "2025-10-02", "2025-11-06", "2025-12-10"] {
        try r.addEntry(E(d, w.dSite, .supervision, "Group Supervision", 60, sup: fall))
    }
    try r.addEntry(E("2025-08-14", w.dSite, .intervention, "Individual Therapy", 50, client: w.a))   // before classes
    try r.addEntry(E("2025-12-22", w.dSite, .intervention, "Individual Therapy", 50, client: w.a))   // winter break
    sems = try r.semesters()
    let s25 = sems.first { $0.name == "Summer 2025" }!, f25 = sems.first { $0.name == "Fall 2025" }!
    expect(s25.autoSupervisorId == summer && f25.autoSupervisorId == fall)
    expect(f25.supervisorName == "Dr. Fall" && f25.start == "2025-08-25" && f25.end == "2026-01-11")
    // Dr. Fall's two August sessions follow her into Fall 2025; Dr. Summer's stay in summer
    expect(s25.byCategory[.supervision] == 300 && f25.byCategory[.supervision] == 360,
           "\(String(describing: s25.byCategory)) \(String(describing: f25.byCategory))")
    expect(s25.byCategory[.intervention] == 50 && f25.byCategory[.intervention] == 50)
    // picking the supervisor by hand overrides the automatic one
    try r.updateSemester(id: f25.id, name: "Fall 2025", start: f25.start, supervisorId: summer)
    expect(try r.semesters().first { $0.id == f25.id }?.supervisorName == "Dr. Summer")
    expectThrows { try r.addSemester(name: "Dup", start: "2025-08-25") }
    expectThrows { try r.addSemester(name: " ", start: "2027-08-23") }
    let next = r.suggestedNextSemester()
    expect(next.name == "Fall 2027" && next.start == "2027-08-23", "\(next)")
    try r.addSemester(name: next.name, start: "2027-08-23")
    expect(try r.semesters().first { $0.name == "Summer 2027" }?.end == "2027-08-22")
}

test("review fixes") {
    // APPIC rounding: each activity rounds up to 15 minutes
    expect(AAPI.credited(50) == 60 && AAPI.credited(60) == 60 && AAPI.credited(61) == 75 && AAPI.credited(1) == 15)
    expect(AAPI.cutoff(today: "2026-11-10") == "2026-09-30")
    var w = try makeWorld(), r = w.repo
    try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Individual Therapy", 50, client: w.a))
    try r.addEntry(E("2026-09-08", w.dSite, .intervention, "Individual Therapy", 50, client: w.a))
    expect(try AAPI.build(r, asOf: "2026-12-01").totals["intervention"] == 2)

    // a recurring occurrence already logged by hand isn't offered again
    w = try makeWorld(); r = w.repo
    let slot = try r.addSlot(weekday: 1, siteId: w.dSite, activity: "Individual Therapy", minutes: 60,
                             clientId: w.a, startDate: "2026-09-01")          // Tuesdays
    try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Individual Therapy", 60, client: w.a))
    var occ = try r.pendingSlotOccurrences(from: "2026-09-01", to: "2026-09-14")
    expect(occ.map(\.date) == ["2026-09-08"], "\(occ.map(\.date))")
    try r.addEntry(E("2026-09-08", w.dSite, .assessment, "Psychodiagnostic", 60, client: w.a))   // other type: still due
    occ = try r.pendingSlotOccurrences(from: "2026-09-01", to: "2026-09-14")
    expect(occ.map(\.date) == ["2026-09-08"] && occ.first?.slot.id == slot)
    // …and old occurrences stay due however long ago (no 28-day window)
    expect(try r.pendingSlotOccurrences(from: "0000-01-01", to: "2026-12-31").count == 17)

    // Undo puts a session back to counted after it was shifted into the future
    w = try makeWorld(); r = w.repo
    let id = try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Individual Therapy", 60, client: w.a))
    let before = EntryInput(entry: try r.entry(id)!, instrumentIds: [])
    var ch = EntryChanges(); ch.shiftDays = 3650
    try r.updateEntries(ids: [id], ch)
    expect(try r.entry(id)!.planned)
    try r.updateEntry(id: id, before)                                  // what Undo does
    expect(try r.entry(id)!.planned == false && r.totals().minutes == 60)
    // an ordinary edit of a planned session still leaves it waiting for confirmation
    var p = before; p.date = Day.add(Day.today(), days: 3); try r.updateEntry(id: id, p)
    var back = EntryInput(entry: try r.entry(id)!, instrumentIds: []); back.date = "2026-09-02"
    try r.updateEntry(id: id, back)
    expect(try r.entry(id)!.planned)

    // a report for a client with no age band is shown, not dropped
    w = try makeWorld(); r = w.repo
    let u = try r.addClient(ClientInput(code: "UU", siteId: w.dSite, ageGroup: "Unknown age", gender: "Female"))
    try r.addReport(clientId: u, date: "2026-09-01", reportType: Vocab.integratedReport)
    let lines = try AAPI.build(r, asOf: "2026-12-01").sections.flatMap(\.lines)
    expect(lines.contains { $0.label.hasPrefix("Age not set") && $0.cells.values.contains { $0.count == 1 } })

    // export tabs honor the As of date
    w = try makeWorld(); r = w.repo
    try r.addEntry(E("2026-09-01", w.dSite, .intervention, "Individual Therapy", 60, client: w.a))
    try r.addEntry(E("2026-10-06", w.dSite, .intervention, "Individual Therapy", 60, client: w.a))
    try r.addEntry(E("2026-10-06", w.dSite, .intervention, "Individual Therapy", 60, client: w.b))
    let cut = Array(try r.entries(until: "2026-09-30").filter { !$0.planned })
    let cs = try Export.clientsAsOf(r, cut, "2026-09-30")
    expect(cs.first { $0.id == w.a }?.nSessions == 1 && cs.first { $0.id == w.a }?.lastSeen == "2026-09-01")
    expect(!cs.contains { $0.id == w.b })                               // first seen after the cutoff
    try r.addSemesters(SemesterPreset.temple.semesters)
    expect(try r.semesters(asOf: "2026-09-30").reduce(0) { $0 + $1.sessions } == 1)
}

print(failures == 0 ? "✓ all \(passes) checks passed" : "✗ \(failures) failed, \(passes) passed")
exit(failures == 0 ? 0 : 1)
