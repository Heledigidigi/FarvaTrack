import Foundation
import Compression

// MARK: - ZIP (xlsx bir ZIP arşividir)

/// En küçük ZIP okuyucu/yazıcı: yazarken sıkıştırmasız (stored), okurken stored ve deflate.
enum ZipArchive {
    enum ZipError: Error { case invalid, unsupported }

    // MARK: Yazma

    static func write(entries: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var central = Data()
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let offset = UInt32(output.count)
            // Yerel başlık
            output.append(le32(0x04034b50))
            output.append(le16(20))            // sürüm
            output.append(le16(0x0800))        // UTF-8 adlar
            output.append(le16(0))             // stored
            output.append(le16(0)); output.append(le16(0x21)) // saat/tarih (1980-01-01)
            output.append(le32(crc))
            output.append(le32(UInt32(entry.data.count)))
            output.append(le32(UInt32(entry.data.count)))
            output.append(le16(UInt16(nameData.count)))
            output.append(le16(0))
            output.append(nameData)
            output.append(entry.data)
            // Merkezi dizin kaydı
            central.append(le32(0x02014b50))
            central.append(le16(20)); central.append(le16(20))
            central.append(le16(0x0800)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc))
            central.append(le32(UInt32(entry.data.count)))
            central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(nameData.count)))
            central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(nameData)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(le32(0x06054b50))
        output.append(le16(0)); output.append(le16(0))
        output.append(le16(UInt16(entries.count))); output.append(le16(UInt16(entries.count)))
        output.append(le32(UInt32(central.count)))
        output.append(le32(centralOffset))
        output.append(le16(0))
        return output
    }

    // MARK: Okuma

    static func read(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.invalid }
        // Sondan merkezi dizin sonu imzasını ara.
        var end = -1
        var index = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_536)
        while index >= lowest {
            if u32(bytes, index) == 0x06054b50 { end = index; break }
            index -= 1
        }
        guard end >= 0 else { throw ZipError.invalid }
        let count = Int(u16(bytes, end + 10))
        var cursor = Int(u32(bytes, end + 16))
        var files: [String: Data] = [:]
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, u32(bytes, cursor) == 0x02014b50 else { throw ZipError.invalid }
            let method = u16(bytes, cursor + 10)
            let compressed = Int(u32(bytes, cursor + 20))
            let uncompressed = Int(u32(bytes, cursor + 24))
            let nameLength = Int(u16(bytes, cursor + 28))
            let extraLength = Int(u16(bytes, cursor + 30))
            let commentLength = Int(u16(bytes, cursor + 32))
            let localOffset = Int(u32(bytes, cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.invalid }
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength

            guard localOffset + 30 <= bytes.count, u32(bytes, localOffset) == 0x04034b50 else { throw ZipError.invalid }
            let localName = Int(u16(bytes, localOffset + 26))
            let localExtra = Int(u16(bytes, localOffset + 28))
            let start = localOffset + 30 + localName + localExtra
            guard start + compressed <= bytes.count else { throw ZipError.invalid }
            let payload = Data(bytes[start..<(start + compressed)])
            switch method {
            case 0: files[name] = payload
            case 8: files[name] = try inflate(payload, expected: uncompressed)
            default: continue
            }
        }
        return files
    }

    /// Ham DEFLATE (Apple'ın COMPRESSION_ZLIB'i başlıksız deflate'tir).
    static func inflate(_ data: Data, expected: Int) throws -> Data {
        if data.isEmpty { return Data() }
        let capacity = max(expected, data.count * 4, 64)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, capacity, s, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw ZipError.unsupported }
        return output.prefix(written)
    }

    private static func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xff), UInt8(value >> 8)]) }
    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8(value >> 24)])
    }
    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xffffffff
    }
}

// MARK: - XLSX

/// Basit xlsx: yalnızca hücre değerleri (metin/sayı). Biçim, formül sonucu dışındaki şeyler yok sayılır.
enum XLSX {
    enum XLSXError: LocalizedError {
        case notSpreadsheet
        case empty

        var errorDescription: String? {
            switch self {
            case .notSpreadsheet: return "Dosya okunamadı. Excel (.xlsx) ya da CSV dosyası seç."
            case .empty: return "Dosyada okunacak satır bulunamadı."
            }
        }
    }

    struct Sheet {
        var name: String
        var rows: [[String]]
    }

    // MARK: Yazma

    static func write(sheets: [Sheet]) -> Data {
        var entries: [(name: String, data: Data)] = []
        let overrides = sheets.indices.map {
            "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        entries.append(("[Content_Types].xml", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\(overrides)</Types>
        """.utf8)))
        entries.append(("_rels/.rels", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """.utf8)))
        let sheetTags = sheets.enumerated().map { index, sheet in
            "<sheet name=\"\(escape(sheet.name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }.joined()
        entries.append(("xl/workbook.xml", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sheetTags)</sheets></workbook>
        """.utf8)))
        let rels = sheets.indices.map {
            "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>"
        }.joined() + "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        entries.append(("xl/_rels/workbook.xml.rels", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
        """.utf8)))
        entries.append(("xl/styles.xml", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>
        """.utf8)))
        for (index, sheet) in sheets.enumerated() {
            var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
            for (r, row) in sheet.rows.enumerated() {
                xml += "<row r=\"\(r + 1)\">"
                for (c, value) in row.enumerated() where !value.isEmpty {
                    let ref = "\(column(c))\(r + 1)"
                    let style = r == 0 ? " s=\"1\"" : ""
                    if let number = Double(value), value.first != "0" || value == "0" || value.hasPrefix("0.") {
                        xml += "<c r=\"\(ref)\"\(style)><v>\(number == number.rounded() ? String(Int(number)) : String(number))</v></c>"
                    } else {
                        xml += "<c r=\"\(ref)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
                    }
                }
                xml += "</row>"
            }
            xml += "</sheetData></worksheet>"
            entries.append(("xl/worksheets/sheet\(index + 1).xml", Data(xml.utf8)))
        }
        return ZipArchive.write(entries: entries)
    }

    // MARK: Okuma

    /// İlk sayfanın satırları.
    static func read(_ data: Data) throws -> [[String]] {
        let files: [String: Data]
        do { files = try ZipArchive.read(data) } catch { throw XLSXError.notSpreadsheet }
        guard let workbook = files["xl/workbook.xml"] else { throw XLSXError.notSpreadsheet }
        let shared = files["xl/sharedStrings.xml"].map(SharedStringsParser.parse) ?? []
        var sheetPath = "xl/worksheets/sheet1.xml"
        if let firstID = FirstSheetParser.firstRelationID(workbook),
           let relsData = files["xl/_rels/workbook.xml.rels"],
           let target = RelationshipParser.target(for: firstID, in: relsData) {
            let clean = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            if files[clean] != nil { sheetPath = clean }
        }
        guard let sheet = files[sheetPath] ?? files.first(where: { $0.key.hasPrefix("xl/worksheets/") && $0.key.hasSuffix(".xml") })?.value else {
            throw XLSXError.notSpreadsheet
        }
        let rows = SheetParser.parse(sheet, shared: shared)
        guard rows.contains(where: { $0.contains { !$0.trimmed.isEmpty } }) else { throw XLSXError.empty }
        return rows
    }

    /// CSV (virgül ya da noktalı virgül, tırnaklı alanlar).
    static func readCSV(_ data: Data) throws -> [[String]] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1254) else {
            throw XLSXError.notSpreadsheet
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        let separator: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = Array(text)
        var i = 0
        while i < iterator.count {
            let ch = iterator[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < iterator.count, iterator[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(ch) }
            } else if ch == "\"" {
                quoted = true
            } else if ch == separator {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else if ch != "\r" {
                field.append(ch)
            }
            i += 1
        }
        iterator.removeAll()
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        guard rows.contains(where: { $0.contains { !$0.trimmed.isEmpty } }) else { throw XLSXError.empty }
        return rows
    }

    static func column(_ index: Int) -> String {
        var n = index + 1
        var name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(UnicodeScalar(65 + r)!) + name
            n = (n - 1) / 26
        }
        return name
    }

    static func columnIndex(_ reference: String) -> Int? {
        var value = 0
        var found = false
        for scalar in reference.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { break }
            value = value * 26 + Int(scalar.value - 64)
            found = true
        }
        return found ? value - 1 : nil
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - XML ayrıştırıcılar

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inItem = false
    private var inText = false
    private var inPhonetic = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "si": inItem = true; current = ""
        case "t": inText = true
        case "rPh": inPhonetic = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem, inText, !inPhonetic { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "si": strings.append(current); inItem = false
        case "t": inText = false
        case "rPh": inPhonetic = false
        default: break
        }
    }
}

private final class FirstSheetParser: NSObject, XMLParserDelegate {
    private var relationID: String?

    static func firstRelationID(_ data: Data) -> String? {
        let delegate = FirstSheetParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.relationID
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        guard relationID == nil, name == "sheet" || name.hasSuffix(":sheet") else { return }
        relationID = attributes["r:id"] ?? attributes.first(where: { $0.key.hasSuffix(":id") })?.value
    }
}

private final class RelationshipParser: NSObject, XMLParserDelegate {
    private let wanted: String
    private var target: String?

    init(wanted: String) { self.wanted = wanted }

    static func target(for id: String, in data: Data) -> String? {
        let delegate = RelationshipParser(wanted: id)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.target
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "Relationship", attributes["Id"] == wanted { target = attributes["Target"] }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    private let shared: [String]
    private var rows: [Int: [Int: String]] = [:]
    private var rowIndex = 0
    private var cellColumn = 0
    private var cellType = ""
    private var value = ""
    private var capturing = false

    init(shared: [String]) { self.shared = shared }

    static func parse(_ data: Data, shared: [String]) -> [[String]] {
        let delegate = SheetParser(shared: shared)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard let maxRow = delegate.rows.keys.max() else { return [] }
        return (0...maxRow).map { r in
            let cells = delegate.rows[r] ?? [:]
            guard let maxColumn = cells.keys.max() else { return [] }
            return (0...maxColumn).map { cells[$0] ?? "" }
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "row":
            if let r = attributes["r"].flatMap(Int.init) { rowIndex = r - 1 }
            cellColumn = 0
        case "c":
            if let ref = attributes["r"], let column = XLSX.columnIndex(ref) { cellColumn = column }
            cellType = attributes["t"] ?? ""
            value = ""
        case "v", "t":
            capturing = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "v", "t":
            capturing = false
        case "c":
            var text = value
            if cellType == "s", let index = Int(value.trimmed), shared.indices.contains(index) { text = shared[index] }
            if cellType == "b" { text = value == "1" ? "DOĞRU" : "YANLIŞ" }
            rows[rowIndex, default: [:]][cellColumn] = text
            cellColumn += 1
        case "row":
            rowIndex += 1
        default: break
        }
    }
}
