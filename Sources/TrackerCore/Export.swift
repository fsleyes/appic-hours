import Foundation

/// Excel export: every sheet as plain values (no formulas).
public enum Export {
    public static func defaultName(asOf: String = Day.today()) -> String { "APPIC Hours \(asOf).xlsx" }

    static func table(_ ws: XSheet, _ headers: [String], _ rows: [[XValue]], fixed: [Int: Double] = [:]) {
        for (i, h) in headers.enumerated() { ws.set(1, i + 1, .text(h), .header) }
        for r in rows { ws.append(r) }
        ws.freeze = (2, 1)
        if !rows.isEmpty { ws.autoFilter = "A1:\(XSheet.colName(headers.count))\(rows.count + 1)" }
        ws.autosize(fixed: fixed)
    }

    static func x(_ v: AAPI.Value) -> XValue {
        switch v {
        case .text(let s): return .text(s)
        case .number(let n): return .number(n)
        }
    }

    static func t(_ s: String?) -> XValue { .text(s ?? "") }

    static func summarySheet(_ ws: XSheet, _ s: AAPI.Summary, _ sections: [AAPI.Section], _ title: String) {
        ws.set(1, 1, .text(title), .title)
        ws.set(2, 1, .text("As of \(s.asOf)  ·  \(s.nEntries) entries"))
        let cols = AAPI.columns.map(\.label)
        var r = 4
        for sec in sections {
            var heads = [sec.title]
            for c in cols { heads += ["\(c) hours", "\(c) \(sec.countLabel)".trimmingCharacters(in: .whitespaces)] }
            for (i, h) in heads.enumerated() { ws.set(r, i + 1, .text(h), .header) }
            r += 1
            for line in sec.lines {
                let indent = String(repeating: "    ", count: max(0, line.level - 1))
                if line.level == 0 {
                    ws.set(r, 1, .text(indent + line.label), .section)
                    for i in 2...heads.count { ws.set(r, i, .empty, .section) }
                } else {
                    let st: XStyle = line.isTotal ? .total : .normal
                    ws.set(r, 1, .text(indent + line.label), st)
                    for (j, c) in cols.enumerated() {
                        let cell = line.cells[c] ?? AAPI.Cell()
                        if line.showHours, let h = cell.hours { ws.set(r, 2 + 2 * j, .number(h), st) }
                        else if line.isTotal { ws.set(r, 2 + 2 * j, .empty, st) }
                        if line.showCount, let n = cell.count { ws.set(r, 3 + 2 * j, .number(Double(n)), st) }
                        else if line.isTotal { ws.set(r, 3 + 2 * j, .empty, st) }
                    }
                }
                r += 1
            }
            r += 1
        }
        ws.width(1, 70)
        for i in 2...7 { ws.width(i, 14) }
        ws.freeze = (4, 2)
    }

    @discardableResult
    /// Clients as they stood on `asOf`: session counts, hours and last-seen from `entries` (already cut off),
    /// closure only if it happened by then; clients first seen later are left out.
    public static func clientsAsOf(_ repo: Repo, _ entries: [Entry], _ asOf: String) throws -> [Client] {
        let by = Dictionary(grouping: entries.filter { $0.clientId != nil }, by: { $0.clientId! })
        return try repo.clients().compactMap { c in
            var c = c
            let es = by[c.id] ?? []
            if es.isEmpty && (c.nSessions > 0 || (c.openedOn ?? "") > asOf) { return nil }
            c.nSessions = es.count; c.minutes = es.reduce(0) { $0 + $1.minutes }; c.lastSeen = es.map(\.date).max()
            if let d = c.closedOn, d > asOf { c.closedOn = nil; c.closureNote = nil }
            return c
        }
    }

    public static func groupsAsOf(_ repo: Repo, _ entries: [Entry], _ asOf: String) throws -> [ClientGroup] {
        let by = Dictionary(grouping: entries.filter { $0.groupId != nil }, by: { $0.groupId! })
        return try repo.groups().compactMap { g in
            var g = g
            let es = by[g.id] ?? []
            if es.isEmpty && g.nSessions > 0 { return nil }
            g.nSessions = es.count; g.minutes = es.reduce(0) { $0 + $1.minutes }; g.lastSeen = es.map(\.date).max()
            if let d = g.closedOn, d > asOf { g.closedOn = nil; g.closureNote = nil }
            return g
        }
    }

    public static func workbook(_ repo: Repo, to url: URL, asOf: String = Day.today()) throws -> URL {
        let s = try AAPI.build(repo, asOf: asOf)
        let wb = XWorkbook()

        summarySheet(wb.add("AAPI Summary"), s, s.sections, "APPIC CLINICAL HOURS — AAPI SUMMARY")
        summarySheet(wb.add("Demographics"), s, [s.demographics],
                     "CLIENT DEMOGRAPHICS (# clients seen in intervention/assessment)")

        let inst = wb.add("Instruments")
        if s.instruments.rows.isEmpty {
            table(inst, ["Instrument", "Total administered", "Reports using it"], [])
        } else {
            table(inst, s.instruments.headers, s.instruments.rows.map { $0.map(x) })
        }

        let sites = wb.add("Sites")
        if !s.sites.rows.isEmpty { table(sites, s.sites.headers, s.sites.rows.map { $0.map(x) }) }

        let ant = wb.add("Anticipated")
        let a = s.anticipated
        ant.set(1, 1, .text("Projection from \(s.asOf) to internship start \(a.internshipStart) (\(AAPI.fmt(a.weeksLeft)) weeks), using the average of the last \(AAPI.fmt(a.windowWeeks)) weeks. Adjust for breaks before entering in the AAPI."))
        for (i, h) in a.table.headers.enumerated() { ant.set(3, i + 1, .text(h), .header) }
        for row in a.table.rows { ant.append(row.map(x)) }
        ant.autosize(fixed: [1: 24])

        table(wb.add("Specify"), ["Date", "Category", "Description", "Hours", "Degree"],
              s.specifyNotes.map { [.text($0.date), .text($0.activity), .text($0.specify), .number($0.hours),
                                    .text($0.degree)] })

        // raw data
        let sess = wb.add("Sessions")
        let entries = try repo.entries(until: s.asOf).filter { !$0.planned }.reversed()
        table(sess, ["Date", "Category", "Clinical Setting", "Setting Type", "Degree", "Service / Activity",
                     "Client / Group", "Client Age", "Hours", "Minutes", "Modality", "Purpose", "Instruments",
                     "Supervisor", "Supervisor Type", "Specify", "Note"],
              entries.map { e in
                  [.date(e.date), .text(e.category.label), .text(e.siteName), .text(e.settingType),
                   .text(e.degree), .text(e.activity), .text(e.clientCode ?? e.groupName ?? ""),
                   t(e.ageGroup), .number(AAPI.round2(Double(AAPI.credited(e.minutes)) / 60)), .number(Double(e.minutes)),
                   .text(e.modality), t(e.purpose), t(e.instruments), t(e.supervisorName),
                   t(e.supervisorType), t(e.specify), t(e.note)]
              }, fixed: [6: 45, 15: 40, 17: 40])

        // Everything below counts only sessions on or before the As of date, like the sheets above.
        let semesters = try repo.semesters(asOf: s.asOf).filter { $0.sessions > 0 }
        table(wb.add("Semesters"), ["Semester", "Starts", "Ends", "Supervisor", "Intervention", "Assessment",
                                    "Supervision", "Support", "Direct Contact", "Total Hours", "# Sessions"],
              semesters.map { m in
                  let h = { (c: HourCategory) -> XValue in .number(AAPI.round2(Double(m.byCategory[c] ?? 0) / 60)) }
                  return [.text(m.name), .date(m.start), m.end.map { .date($0) } ?? .text(""), t(m.supervisorName),
                          h(.intervention), h(.assessment), h(.supervision), h(.support),
                          .number(AAPI.round2(Double(m.directMinutes) / 60)), .number(AAPI.round2(Double(m.minutes) / 60)),
                          .number(Double(m.sessions))]
              })

        table(wb.add("Clients"), ["Client ID / Pseudonym", "Client Type", "Clinical Setting", "Degree", "Client Age",
                                  "Race / Ethnicity", "Gender", "Sexual Orientation", "Disabilities",
                                  "Opened", "Closed", "Closure note", "# Sessions", "Hours", "Last seen", "Notes"],
              try clientsAsOf(repo, Array(entries), s.asOf).map { c in
                  [.text(c.code), .text(c.kind.label), .text(c.siteName), .text(c.degree), .text(c.ageGroup), t(c.race), t(c.gender),
                   t(c.orientation), .text(c.disabilities.joined(separator: "; ")), t(c.openedOn), t(c.closedOn),
                   t(c.closureNote), .number(Double(c.nSessions)), .number(AAPI.round2(Double(c.minutes) / 60)),
                   t(c.lastSeen), t(c.notes)]
              })

        table(wb.add("Groups"), ["Group / Family / Couple", "Type", "Clinical Setting", "Degree", "Age",
                                 "Closed", "# Sessions", "Hours", "Last seen"],
              try groupsAsOf(repo, Array(entries), s.asOf).map { g in
                  [.text(g.name), .text(g.groupType), .text(g.siteName), .text(g.degree), t(g.ageGroup),
                   t(g.closedOn), .number(Double(g.nSessions)), .number(AAPI.round2(Double(g.minutes) / 60)),
                   t(g.lastSeen)]
              })

        table(wb.add("Reports"), ["Date", "Client", "Report Type", "Purpose", "Age Group", "Degree",
                                  "Instruments", "Note"],
              try repo.reports().filter { $0.date <= s.asOf }.map { r in
                  [.text(r.date), .text(r.clientCode), .text(r.reportType), .text(r.purpose),
                   .text(Vocab.ageBand(r.ageGroup) ?? "Unknown"), .text(r.degree), t(r.instruments), t(r.note)]
              })

        table(wb.add("Supervisors"), ["Name", "Supervisor Type", "Site"],
              try repo.supervisors().map { [.text($0.name), .text($0.supervisorType), t($0.siteName)] })

        table(wb.add("Settings"), ["Clinical Setting Name", "Setting Type", "Degree Program", "Start", "End"],
              try repo.sites().map { [.text($0.name), .text($0.settingType), .text($0.degreeProgram),
                                      t($0.startDate), t($0.endDate)] })

        try wb.save(to: url)
        return url
    }
}
