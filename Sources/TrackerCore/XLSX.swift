import Foundation

// MARK: - Writer

public enum XStyle: Int { case normal = 0, header, section, total, date, title, bold }

public enum XValue {
    case text(String), number(Double), date(String), empty
}

/// A worksheet built in memory, then serialised to SpreadsheetML.
public final class XSheet {
    public let name: String
    var cells: [Int: [Int: (XValue, XStyle)]] = [:]    // row → col → value (1-based)
    var widths: [Int: Double] = [:]
    public var freeze: (row: Int, col: Int)?           // first unfrozen cell, e.g. (2,1) = "A2"
    public var autoFilter: String?
    public private(set) var maxRow = 0

    init(name: String) { self.name = name }

    public func set(_ r: Int, _ c: Int, _ v: XValue, _ style: XStyle = .normal) {
        cells[r, default: [:]][c] = (v, style)
        maxRow = max(maxRow, r)
    }

    public func style(_ r: Int, _ c: Int, _ style: XStyle) {
        let v = cells[r]?[c]?.0 ?? .empty
        set(r, c, v, style)
    }

    public func append(_ values: [XValue], _ style: XStyle = .normal) {
        let r = maxRow + 1
        for (i, v) in values.enumerated() { set(r, i + 1, v, style) }
        if values.isEmpty { maxRow = r }
    }

    public func width(_ col: Int, _ w: Double) { widths[col] = w }

    /// Size columns to their longest value.
    public func autosize(cap: Double = 60, fixed: [Int: Double] = [:]) {
        var maxLen: [Int: Int] = [:]
        for (_, cols) in cells {
            for (c, (v, _)) in cols {
                let len: Int
                switch v {
                case .text(let s): len = s.count
                case .number(let n): len = AAPI.fmt(n).count
                case .date: len = 10
                case .empty: len = 0
                }
                maxLen[c] = max(maxLen[c] ?? 0, len)
            }
        }
        for (c, l) in maxLen {
            let w = fixed[c] ?? Double(l)
            widths[c] = min(cap, max(8, w + 2))
        }
    }

    static func colName(_ c: Int) -> String {
        var c = c, s = ""
        while c > 0 {
            let r = (c - 1) % 26
            s = String(UnicodeScalar(65 + r)!) + s
            c = (c - 1) / 26
        }
        return s
    }

    static func esc(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                if ch.value < 0x20 && ch != "\t" && ch != "\n" && ch != "\r" { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    func xml() -> String {
        var x = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        x += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">"#
        x += "<sheetViews><sheetView workbookViewId=\"0\">"
        if let f = freeze {
            let ref = "\(Self.colName(f.col))\(f.row)"
            let xs = f.col - 1, ys = f.row - 1
            let pane = xs > 0 && ys > 0 ? "bottomRight" : (ys > 0 ? "bottomLeft" : "topRight")
            x += "<pane"
            if xs > 0 { x += " xSplit=\"\(xs)\"" }
            if ys > 0 { x += " ySplit=\"\(ys)\"" }
            x += " topLeftCell=\"\(ref)\" activePane=\"\(pane)\" state=\"frozen\"/>"
            x += "<selection pane=\"\(pane)\" activeCell=\"\(ref)\" sqref=\"\(ref)\"/>"
        }
        x += "</sheetView></sheetViews>"
        if !widths.isEmpty {
            x += "<cols>"
            for c in widths.keys.sorted() {
                x += "<col min=\"\(c)\" max=\"\(c)\" width=\"\(widths[c]!)\" customWidth=\"1\"/>"
            }
            x += "</cols>"
        }
        x += "<sheetData>"
        for r in cells.keys.sorted() {
            x += "<row r=\"\(r)\">"
            for c in cells[r]!.keys.sorted() {
                let (v, st) = cells[r]![c]!
                let ref = "\(Self.colName(c))\(r)"
                let s = st == .normal ? "" : " s=\"\(st.rawValue)\""
                switch v {
                case .text(let t):
                    x += "<c r=\"\(ref)\"\(s) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(Self.esc(t))</t></is></c>"
                case .number(let n):
                    x += "<c r=\"\(ref)\"\(s)><v>\(n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n))</v></c>"
                case .date(let iso):
                    x += "<c r=\"\(ref)\" s=\"\(XStyle.date.rawValue)\"><v>\(Int(Day.excelSerial(iso)))</v></c>"
                case .empty:
                    x += "<c r=\"\(ref)\"\(s)/>"
                }
            }
            x += "</row>"
        }
        x += "</sheetData>"
        if let af = autoFilter { x += "<autoFilter ref=\"\(af)\"/>" }
        x += "</worksheet>"
        return x
    }
}

public final class XWorkbook {
    public private(set) var sheets: [XSheet] = []
    public init() {}

    public func add(_ name: String) -> XSheet {
        let s = XSheet(name: String(name.prefix(31)))
        sheets.append(s)
        return s
    }

    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts>
    <fonts count="4">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="14"/><name val="Calibri"/></font>
    </fonts>
    <fills count="5">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF1F3864"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/><bgColor indexed="64"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F2"/><bgColor indexed="64"/></patternFill></fill>
    </fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="7">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment wrapText="1" vertical="center"/></xf>
    <xf numFmtId="0" fontId="2" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
    <xf numFmtId="0" fontId="2" fillId="4" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    </cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """

    public func data() -> Data {
        var files: [(String, Data)] = []
        var ct = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
        for i in sheets.indices {
            ct += "<Override PartName=\"/xl/worksheets/sheet\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        ct += "</Types>"
        files.append(("[Content_Types].xml", Data(ct.utf8)))
        files.append(("_rels/.rels", Data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#.utf8)))

        var wb = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>"#
        var rels = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        for (i, s) in sheets.enumerated() {
            wb += "<sheet name=\"\(XSheet.esc(s.name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
            rels += "<Relationship Id=\"rId\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i + 1).xml\"/>"
        }
        wb += "</sheets></workbook>"
        rels += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
        files.append(("xl/workbook.xml", Data(wb.utf8)))
        files.append(("xl/_rels/workbook.xml.rels", Data(rels.utf8)))
        files.append(("xl/styles.xml", Data(Self.styles.utf8)))
        for (i, s) in sheets.enumerated() {
            files.append(("xl/worksheets/sheet\(i + 1).xml", Data(s.xml().utf8)))
        }
        return Zip.write(files)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data().write(to: url, options: .atomic)
    }
}

// MARK: - Reader (for batch-importing clients)

public enum XLSXReader {
    /// Rows of the "Clients" sheet if present, else the first sheet. Cells are String or Double.
    public static func rows(from url: URL) throws -> [[Any?]] {
        let files = try Zip.read(try Data(contentsOf: url))
        guard let wbData = files["xl/workbook.xml"] else {
            throw Zip.ReadError(message: "That doesn't look like an Excel workbook.")
        }
        let sheets = XMLCollect.elements(wbData, named: "sheet")   // [attrs]
        let rels = XMLCollect.elements(files["xl/_rels/workbook.xml.rels"] ?? Data(), named: "Relationship")
        let pick = sheets.first { $0["name"] == "Clients" } ?? sheets.first
        var path = "xl/worksheets/sheet1.xml"
        if let rid = pick?["r:id"], let rel = rels.first(where: { $0["Id"] == rid }), let t = rel["Target"] {
            path = t.hasPrefix("/") ? String(t.dropFirst()) : "xl/" + t
        }
        let shared = SharedStrings.parse(files["xl/sharedStrings.xml"] ?? Data())
        guard let sheet = files[path] else { throw Zip.ReadError(message: "Couldn't find the worksheet.") }
        return SheetParser.parse(sheet, shared: shared)
    }
}

private final class XMLCollect: NSObject, XMLParserDelegate {
    let target: String
    var found: [[String: String]] = []
    init(_ t: String) { target = t }
    static func elements(_ data: Data, named name: String) -> [[String: String]] {
        let d = XMLCollect(name)
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.found
    }
    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if el == target { found.append(attributes) }
    }
}

private final class SharedStrings: NSObject, XMLParserDelegate {
    var strings: [String] = []
    var current = "", inT = false
    static func parse(_ data: Data) -> [String] {
        let d = SharedStrings()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.strings
    }
    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if el == "si" { current = "" }
        if el == "t" { inT = true }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inT { current += s } }
    func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        if el == "t" { inT = false }
        if el == "si" { strings.append(current) }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [Int: [Int: Any]] = [:]
    var cellRef = "", cellType = "", text = "", capture = false
    init(shared: [String]) { self.shared = shared }

    static func parse(_ data: Data, shared: [String]) -> [[Any?]] {
        let d = SheetParser(shared: shared)
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        guard let maxRow = d.rows.keys.max() else { return [] }
        return (1...maxRow).map { r in
            let cols = d.rows[r] ?? [:]
            let maxC = cols.keys.max() ?? 0
            return maxC == 0 ? [] : (1...maxC).map { cols[$0] }
        }
    }

    static func split(_ ref: String) -> (Int, Int) {
        var col = 0, rowStr = ""
        for ch in ref {
            if let a = ch.asciiValue, a >= 65 && a <= 90 { col = col * 26 + Int(a - 64) } else { rowStr.append(ch) }
        }
        return (Int(rowStr) ?? 0, col)
    }

    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?,
                attributes a: [String: String] = [:]) {
        if el == "c" { cellRef = a["r"] ?? ""; cellType = a["t"] ?? "n"; text = "" }
        if el == "v" || el == "t" { capture = true }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if capture { text += s } }
    func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        if el == "v" || el == "t" { capture = false }
        if el == "c" {
            let (r, c) = Self.split(cellRef)
            guard r > 0, c > 0, !text.isEmpty else { return }
            let v: Any
            switch cellType {
            case "s": v = Int(text).flatMap { $0 < shared.count ? shared[$0] : nil } ?? ""
            case "inlineStr", "str", "d": v = text
            case "b": v = text == "1" ? "TRUE" : "FALSE"
            default: v = Double(text) ?? text
            }
            rows[r, default: [:]][c] = v
        }
    }
}

// MARK: - CSV

public enum CSV {
    /// RFC-4180-ish parser (quotes, embedded delimiters/newlines).
    public static func parse(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        var it = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character? = nil
        while let ch = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let nx = it.next() {
                        if nx == "\"" { field.append("\"") } else { inQuotes = false; pending = nx }
                    } else { inQuotes = false }
                } else { field.append(ch) }
            } else if ch == "\"" && field.isEmpty {
                inQuotes = true
            } else if ch == delimiter {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    public static func line(_ fields: [String]) -> String {
        fields.map { f in
            f.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
        }.joined(separator: ",")
    }
}
