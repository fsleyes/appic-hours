import Foundation

/// Batch-add clients: parse pasted rows / CSV / XLSX into validated client records.
/// Forgiving on input (loose headers, case-insensitive values, aliases, numeric ages),
/// strict on output.
public enum Batch {
    public static let fields: [(key: String, header: String)] = [
        ("code", "Client ID / Pseudonym"),
        ("site", "Clinical Setting"),
        ("age_group", "Client Age"),
        ("race", "Race / Ethnicity"),
        ("gender", "Gender"),
        ("orientation", "Sexual Orientation"),
        ("disabilities", "Disabilities (separate with ;)"),
        ("opened_on", "Case Opened (YYYY-MM-DD)"),
        ("notes", "Notes"),
    ]
    public static let fieldNames = fields.map(\.key)
    static let ignore = "_ignore"

    // Ordered (prefix matching walks this in order).
    static let headerAliases: [(String, String)] = [
        ("clientidpseudonym", "code"), ("clientid", "code"), ("id", "code"), ("code", "code"),
        ("client", "code"), ("pseudonym", "code"), ("initials", "code"), ("clientcode", "code"),
        ("clinicalsetting", "site"), ("site", "site"), ("setting", "site"), ("clinic", "site"),
        ("clientage", "age_group"), ("age", "age_group"), ("agegroup", "age_group"), ("ageband", "age_group"),
        ("raceethnicity", "race"), ("race", "race"), ("ethnicity", "race"),
        ("gender", "gender"), ("genderidentity", "gender"),
        ("sexualorientation", "orientation"), ("orientation", "orientation"),
        ("disabilitytype", "disabilities"), ("disability", "disabilities"),
        ("disabilities", "disabilities"), ("disabilitiesseparatewith", "disabilities"),
        ("caseopened", "opened_on"), ("caseopenedyyyymmdd", "opened_on"), ("opened", "opened_on"),
        ("openedon", "opened_on"), ("intake", "opened_on"), ("intakedate", "opened_on"),
        ("startdate", "opened_on"),
        ("notes", "notes"), ("note", "notes"),
        // client type (not a grid column — comes from an imported file or the sheet default)
        ("clienttype", "kind"), ("type", "kind"), ("kind", "kind"), ("therapyorassessment", "kind"),
        // case closed (not a grid column): a date, or yes/no
        ("closedon", "closed"), ("caseclosed", "closed"), ("closeddate", "closed"), ("dateclosed", "closed"),
        ("closed", "closed"),
        ("hasdisability", ignore), ("degreeauto", ignore), ("degree", ignore),
    ]
    static let headerAliasDict = Dictionary(headerAliases, uniquingKeysWith: { a, _ in a })

    static let R = Vocab.races, D = Vocab.disabilities
    static let valueAliases: [String: [String: String]] = [
        "race": [
            "black": R[0], "african american": R[0], "african": R[0],
            "asian": R[1], "asian american": R[1], "pacific islander": R[1], "aapi": R[1],
            "latino": R[2], "latina": R[2], "latinx": R[2], "latine": R[2], "hispanic": R[2], "latino/a": R[2],
            "native american": R[3], "american indian": R[3], "alaska native": R[3], "indigenous": R[3],
            "white": R[4], "caucasian": R[4], "european": R[4],
            "biracial": R[5], "multiracial": R[5], "mixed": R[5], "multi": R[5],
        ],
        "gender": [
            "m": "Male", "man": "Male", "boy": "Male", "cis man": "Male",
            "f": "Female", "woman": "Female", "girl": "Female", "cis woman": "Female",
            "trans": "Transgender", "transgender": "Transgender", "trans man": "Transgender",
            "trans woman": "Transgender",
            "nonbinary": "Other", "non-binary": "Other", "nb": "Other", "genderqueer": "Other",
        ],
        "orientation": [
            "straight": "Heterosexual", "hetero": "Heterosexual", "het": "Heterosexual",
            "bi": "Bisexual", "queer": "Other", "pansexual": "Other", "pan": "Other",
            "asexual": "Other", "ace": "Other",
        ],
        "age_group": [
            "adult": "18-64 years old", "adults": "18-64 years old",
            "older adult": "65+ years old", "older adults": "65+ years old", "senior": "65+ years old",
            "adolescent": "13-17 years old", "adolescents": "13-17 years old",
            "teen": "13-17 years old", "teenager": "13-17 years old",
            "child": "6-12 years old", "children": "6-12 years old", "school age": "6-12 years old",
            "preschool": "3-5 years old", "infant": "0-2 years old", "toddler": "0-2 years old",
            "unknown": "Unknown age", "?": "Unknown age",
        ],
        "disabilities": [
            "physical": D[0], "orthopedic": D[0],
            "blind": D[1], "visually impaired": D[1], "visual": D[1],
            "deaf": D[2], "hard of hearing": D[2], "hearing": D[2],
            "learning": D[3], "cognitive": D[3], "ld": D[3],
            "developmental": D[4], "dd": D[4],
            "smi": D[5], "serious mental illness": D[5],
        ],
    ]
    static let canonical: [String: [String]] = [
        "race": Vocab.races, "gender": Vocab.genders, "orientation": Vocab.orientations,
        "age_group": Vocab.clientAges, "disabilities": Vocab.disabilities,
    ]
    static let noneWords: Set<String> = ["", "none", "no", "n/a", "na", "-", "nil"]

    public struct ParsedRow: Identifiable, Sendable {
        public var id = UUID()
        public var raw: [String: String] = [:]
        public var values: [String: String] = [:]     // normalised; disabilities joined with "; "
        public var disabilities: [String] = []
        public var errors: [String: String] = [:]
        public var ok: Bool { errors.isEmpty }
    }

    // MARK: headers

    static func normHeader(_ h: String) -> String {
        String(h.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
    }

    public static func mapHeaders(_ row: [String]) -> [String?] {
        row.map { h in
            let n = normHeader(h)
            if let f = headerAliasDict[n] { return f }
            for (key, val) in headerAliases where key.count > 3 && n.hasPrefix(key) { return val }
            return nil
        }
    }

    public static func looksLikeHeader(_ row: [String]) -> Bool {
        let mapped = mapHeaders(row).compactMap { $0 }
        return mapped.count >= 2 || (row.count == 1 && !mapped.isEmpty)
    }

    // MARK: values

    static func match(_ field: String, _ raw: String) -> String? {
        let low = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let canon = canonical[field] ?? []
        if let c = canon.first(where: { $0.lowercased() == low }) { return c }
        if let a = valueAliases[field]?[low] { return a }
        if low.count >= 2 {
            let hits = canon.filter { $0.lowercased().hasPrefix(low) }
            if hits.count == 1 { return hits[0] }
        }
        if low.count >= 4 {
            let hits = canon.filter { $0.lowercased().contains(low) }
            if hits.count == 1 { return hits[0] }
        }
        return nil
    }

    public static func ageFromNumber(_ n: Double) -> String {
        if n < 3 { return "0-2 years old" }
        if n < 6 { return "3-5 years old" }
        if n < 13 { return "6-12 years old" }
        if n < 18 { return "13-17 years old" }
        if n < 65 { return "18-64 years old" }
        return "65+ years old"
    }

    static let reNumber = try! Regex(#"^\d+(\.\d+)?$"#)
    static let reRange = try! Regex(#"^(\d+)\s*[-–]\s*(\d+)(\s*(years?( old)?|yrs?|y/?o))?$"#).ignoresCase()
    static let rePlus = try! Regex(#"^(\d+)\s*\+(\s*(years?( old)?|yrs?))?$"#).ignoresCase()

    static func cap(_ m: Regex<AnyRegexOutput>.Match, _ i: Int) -> String {
        m.output[i].substring.map(String.init) ?? ""
    }

    static func parseAge(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if (try? reNumber.wholeMatch(in: s)) != nil, let n = Double(s) { return ageFromNumber(n) }
        if let m = try? reRange.wholeMatch(in: s) {
            let cand = "\(cap(m, 1))-\(cap(m, 2)) years old"
            if Vocab.clientAges.contains(cand) { return cand }
        }
        if let m = try? rePlus.wholeMatch(in: s) {
            let cand = "\(cap(m, 1))+ years old"
            if Vocab.clientAges.contains(cand) { return cand }
        }
        return match("age_group", s)
    }

    static let reISO = try! Regex(#"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})( \d{1,2}:\d{2}:\d{2})?$"#)
    static let reUS4 = try! Regex(#"^(\d{1,2})/(\d{1,2})/(\d{4})$"#)
    static let reUS2 = try! Regex(#"^(\d{1,2})/(\d{1,2})/(\d{2})$"#)
    static let reUSNoYear = try! Regex(#"^(\d{1,2})/(\d{1,2})$"#)

    /// ISO date from common formats, or nil.
    public static func parseDate(_ raw: String, defaultYear: Int? = nil) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let m = try? reISO.wholeMatch(in: s) {
            return Day.iso(year: Int(cap(m, 1))!, month: Int(cap(m, 2))!, day: Int(cap(m, 3))!)
        }
        if let m = try? reUS4.wholeMatch(in: s) {
            return Day.iso(year: Int(cap(m, 3))!, month: Int(cap(m, 1))!, day: Int(cap(m, 2))!)
        }
        if let m = try? reUS2.wholeMatch(in: s) {
            let yy = Int(cap(m, 3))!
            return Day.iso(year: yy < 69 ? 2000 + yy : 1900 + yy, month: Int(cap(m, 1))!, day: Int(cap(m, 2))!)
        }
        if let y = defaultYear, let m = try? reUSNoYear.wholeMatch(in: s) {
            return Day.iso(year: y, month: Int(cap(m, 1))!, day: Int(cap(m, 2))!)
        }
        // "Nov 6, 2026", "November 6 2026", "6 Nov 2026"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["MMM d, yyyy", "MMM d yyyy", "MMMM d, yyyy", "MMMM d yyyy", "d MMM yyyy", "d MMMM yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return Day.iso(d) }
        }
        return nil
    }

    static func cellString(_ v: Any?) -> String {
        switch v {
        case nil: return ""
        case let d as Double: return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case let i as Int: return String(i)
        case let s as String: return s.trimmingCharacters(in: .whitespacesAndNewlines)
        default: return "\(v!)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: parse

    /// Parse a table (first row may be a header). Blank rows are dropped.
    public static func parseRows(_ input: [[Any?]], repo: Repo? = nil, defaultSite: String? = nil,
                                 hasHeader: Bool? = nil, defaultKind: ClientKind = .therapy) -> [ParsedRow] {
        var rows = input.filter { $0.contains { !cellString($0).isEmpty } }
        guard !rows.isEmpty else { return [] }
        let header = hasHeader ?? looksLikeHeader(rows[0].map(cellString))
        let colmap: [String?]
        if header {
            colmap = mapHeaders(rows[0].map(cellString))
            rows.removeFirst()
        } else {
            colmap = Array(fieldNames.prefix(rows.map(\.count).max() ?? 0))
        }
        let sites = ((try? repo?.sites()) ?? nil) ?? []
        let siteNames = Dictionary(sites.map { ($0.name.lowercased(), $0.name) }, uniquingKeysWith: { a, _ in a })
        let existing = ((try? repo?.existingClientCodes()) ?? nil) ?? []
        var seenCodes: [String: Int] = [:]

        var out: [ParsedRow] = []
        for (idx, r) in rows.enumerated() {
            var raw: [String: String] = [:]
            var openedSerial: Double?
            for (f, v) in zip(colmap, r) {
                guard let f, f != ignore else { continue }
                let s = cellString(v)
                if f == "opened_on", let d = v as? Double { openedSerial = d }
                if !s.isEmpty && (raw[f] ?? "").isEmpty { raw[f] = s }
            }
            var p = ParsedRow(raw: raw)
            fill(&p, raw: raw, openedSerial: openedSerial, hasRepo: repo != nil, siteNames: siteNames,
                 existing: existing, seenCodes: &seenCodes, defaultSite: defaultSite, idx: idx + 1)
            if p.values["kind"] == nil { p.values["kind"] = defaultKind.rawValue }
            out.append(p)
        }
        return out
    }

    /// "therapy", "t", "intervention" → therapy; "assessment", "a", "testing", "eval" → assessment.
    public static func parseKind(_ raw: String) -> ClientKind? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if ["therapy", "t", "tx", "intervention", "therapy client", "counseling", "psychotherapy"].contains(s) { return .therapy }
        if ["assessment", "a", "assess", "testing", "eval", "evaluation", "assessment client"].contains(s) { return .assessment }
        if s.hasPrefix("ther") { return .therapy }
        if s.hasPrefix("assess") { return .assessment }
        return nil
    }

    static func fill(_ p: inout ParsedRow, raw: [String: String], openedSerial: Double?, hasRepo: Bool,
                     siteNames: [String: String], existing: Set<String>, seenCodes: inout [String: Int],
                     defaultSite: String?, idx: Int) {
        let code = raw["code"] ?? ""
        if code.isEmpty {
            p.errors["code"] = "Client ID is required."
        } else if existing.contains(code.lowercased()) {
            p.errors["code"] = "\(code) already exists."
        } else if let first = seenCodes[code.lowercased()] {
            p.errors["code"] = "Duplicate of row \(first)."
        } else {
            seenCodes[code.lowercased()] = idx
        }
        p.values["code"] = code

        var site = raw["site"] ?? defaultSite ?? ""
        if site.isEmpty {
            p.errors["site"] = "Site is required."
        } else if hasRepo {
            var name = siteNames[site.lowercased()]
            if name == nil {
                let hits = siteNames.filter { $0.key.hasPrefix(site.lowercased()) }.map(\.value)
                name = hits.count == 1 ? hits[0] : nil
            }
            if name == nil { p.errors["site"] = "No site named '\(site)' (add it in Setup first)." }
            site = name ?? site
        }
        p.values["site"] = site

        let ageRaw = raw["age_group"] ?? ""
        let age = ageRaw.isEmpty ? nil : parseAge(ageRaw)
        if ageRaw.isEmpty {
            p.errors["age_group"] = "Age is required (use 'Unknown' if needed)."
        } else if age == nil {
            p.errors["age_group"] = "Unrecognised age '\(ageRaw)'."
        }
        p.values["age_group"] = age ?? ageRaw

        for f in ["race", "gender", "orientation"] {
            let v = raw[f] ?? ""
            if v.isEmpty || noneWords.subtracting(["no"]).contains(v.lowercased()) { continue }
            let m = match(f, v)
            if m == nil { p.errors[f] = "Unrecognised value '\(v)'." }
            p.values[f] = m ?? v
        }

        let disRaw = raw["disabilities"] ?? ""
        var dis: [String] = []
        if !noneWords.contains(disRaw.lowercased()) {
            for part in disRaw.split(whereSeparator: { ";,|/\n".contains($0) }) {
                let s = part.trimmingCharacters(in: .whitespaces)
                if s.isEmpty || noneWords.contains(s.lowercased()) { continue }
                if let m = match("disabilities", s) { dis.append(m) }
                else { p.errors["disabilities"] = "Unrecognised disability '\(s)'." }
            }
        }
        p.disabilities = dis
        p.values["disabilities"] = dis.joined(separator: "; ")

        if let serial = openedSerial, serial > 1 {
            p.values["opened_on"] = Day.fromExcelSerial(serial)
        } else if let o = raw["opened_on"], !o.isEmpty {
            if let d = parseDate(o) { p.values["opened_on"] = d }
            else { p.errors["opened_on"] = "Unrecognised date '\(o)'." }
        }
        if let n = raw["notes"], !n.isEmpty { p.values["notes"] = n }
        if let c = raw["closed"], !c.isEmpty {
            let low = c.lowercased()
            if let d = parseDate(c) { p.values["closed"] = "1"; p.values["closed_on"] = d }
            else if ["yes", "y", "true", "x", "closed", "1"].contains(low) { p.values["closed"] = "1" }
            else if !["no", "n", "false", "open", "0"].contains(low) {
                p.errors["code"] = (p.errors["code"].map { $0 + " " } ?? "") + "Unrecognised closed value '\(c)' (use a date, or yes/no)."
            }
        }
        if let k = raw["kind"], !k.isEmpty {
            if let kind = parseKind(k) { p.values["kind"] = kind.rawValue }
            else { p.errors["code"] = (p.errors["code"].map { $0 + " " } ?? "") + "Unrecognised client type '\(k)' (use Therapy or Assessment)." }
        }
    }

    /// Parse clipboard text (tab-separated from Excel/Sheets, or CSV).
    public static func parseText(_ text: String, repo: Repo? = nil, defaultSite: String? = nil) -> [ParsedRow] {
        let delim: Character = text.contains("\t") ? "\t" : ","
        return parseRows(CSV.parse(text, delimiter: delim), repo: repo, defaultSite: defaultSite)
    }

    public static func readFile(_ url: URL) throws -> [[Any?]] {
        if ["xlsx", "xlsm"].contains(url.pathExtension.lowercased()) {
            return try XLSXReader.rows(from: url)
        }
        var text = try String(contentsOf: url, encoding: .utf8)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let sample = text.prefix(4096)
        let delim: Character = sample.filter { $0 == "\t" }.count > sample.filter { $0 == "," }.count ? "\t" : ","
        return CSV.parse(text, delimiter: delim)
    }

    public static func toClientInputs(_ repo: Repo, _ parsed: [ParsedRow]) throws -> [ClientInput] {
        try parsed.map { p in
            guard p.ok else { throw ValidationError("Fix the highlighted rows first.") }
            let v = p.values
            return ClientInput(code: v["code"] ?? "", siteId: repo.siteId(named: v["site"] ?? ""),
                               ageGroup: v["age_group"] ?? "", race: v["race"], gender: v["gender"],
                               orientation: v["orientation"], disabilities: p.disabilities,
                               notes: v["notes"], openedOn: v["opened_on"],
                               kind: v["kind"].flatMap(ClientKind.init(rawValue:)) ?? .therapy)
        }
    }

    public static func templateCSV() -> String { CSV.line(fields.map(\.header)) + "\n" }

    // MARK: batch sessions

    /// Dates from free text: one per line or separated by commas/semicolons.
    /// Returns (dates, unparsed tokens). Year-less "11/3" uses `defaultYear`.
    public static func parseDateList(_ text: String, defaultYear: Int = Day.year(Day.today()))
        -> (dates: [String], bad: [String]) {
        var dates: [String] = [], bad: [String] = []
        let tokens = text.components(separatedBy: CharacterSet(charactersIn: "\n;\t"))
            .flatMap { line -> [String] in
                // allow comma separation, but not inside "Nov 6, 2026"
                line.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
                    ? [line] : line.components(separatedBy: ",")
            }
        for t in tokens {
            let s = t.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if let d = parseDate(s, defaultYear: defaultYear) { dates.append(d) } else { bad.append(s) }
        }
        return (dates, bad)
    }

    /// `count` dates, `everyDays` apart, starting at `start`.
    public static func repeatingDates(start: String, count: Int, everyDays: Int = 7) -> [String] {
        (0..<max(0, count)).map { Day.add(start, days: $0 * everyDays) }
    }
}
