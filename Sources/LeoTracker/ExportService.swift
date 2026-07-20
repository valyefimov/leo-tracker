import Foundation

enum ExportService {
    static func csv(entries: [TimeEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = entries.map { entry in
            [
                csvDate(entry.startedAt),
                escape(entry.project),
                escape(entry.task),
                formatter.string(from: entry.startedAt),
                entry.endedAt.map(formatter.string(from:)) ?? "",
                String(exportUnits(entry.duration)),
                entry.duration.clockText
            ].joined(separator: ",")
        }
        return (["Date,Project,Task,Started,Ended,Units (100 = 1 hour),Duration"] + rows).joined(separator: "\n")
    }

    /// A genuine XLSX workbook (ZIP + OOXML), so Excel opens it without the XML/extension warning.
    static func xlsx(entries: [TimeEntry]) -> Data {
        let header = stringRow(["Date", "Project", "Task", "Started", "Ended", "Units (100 = 1 hour)", "Duration"], number: 1)
        let rows = entries.enumerated().map { index, entry in
            dataRow(entry, number: index + 2)
        }.joined(separator: "\n")
        let finalRow = max(1, entries.count + 1)
        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:G\(finalRow)"/><sheetViews><sheetView workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="1" width="14" customWidth="1"/><col min="2" max="3" width="24" customWidth="1"/><col min="4" max="5" width="22" customWidth="1"/><col min="6" max="6" width="23" customWidth="1"/><col min="7" max="7" width="14" customWidth="1"/></cols><sheetData>
        <row r="1">\(header)</row>
        \(rows)
        </sheetData><autoFilter ref="A1:G\(finalRow)"/></worksheet>
        """
        let files: [(String, String)] = [
            ("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"),
            ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            ("xl/workbook.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Report\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"),
            ("xl/_rels/workbook.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"),
            ("xl/worksheets/sheet1.xml", sheet)
        ]
        return ZipArchive.store(files)
    }

    static func exportUnits(_ duration: TimeInterval) -> Int { Int((duration / 36).rounded()) }

    private static func dateOnly(_ date: Date) -> String { formatted(date, format: "yyyy-MM-dd") }
    private static func csvDate(_ date: Date) -> String { dateOnly(date) }
    private static func dateTime(_ date: Date) -> String { formatted(date, format: "yyyy-MM-dd HH:mm:ss") }
    private static func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = format
        return formatter.string(from: date)
    }
    private static func dataRow(_ entry: TimeEntry, number: Int) -> String {
        let values = [dateOnly(entry.startedAt), entry.project, entry.task, dateTime(entry.startedAt), entry.endedAt.map(dateTime) ?? "", entry.duration.clockText]
        let cells = values.enumerated().map { stringCell($0.element, reference: cellReference(column: $0.offset, row: number)) }
        let unitCell = numberCell(exportUnits(entry.duration), reference: cellReference(column: 5, row: number))
        return "<row r=\(number)>\(cells.prefix(5).joined())\(unitCell)\(cells[5])</row>"
    }
    private static func stringRow(_ values: [String], number: Int) -> String {
        values.enumerated().map { stringCell($0.element, reference: cellReference(column: $0.offset, row: number)) }.joined()
    }
    private static func cellReference(column: Int, row: Int) -> String {
        "\(Character(UnicodeScalar(65 + column)!))\(row)"
    }
    private static func numberCell(_ value: Int, reference: String) -> String { "<c r=\"\(reference)\" t=\"n\"><v>\(value)</v></c>" }
    private static func stringCell(_ value: String, reference: String) -> String { "<c r=\"\(reference)\" t=\"inlineStr\"><is><t>\(xml(value))</t></is></c>" }
    private static func escape(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
    private static func xml(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
}

private enum ZipArchive {
    static func store(_ files: [(String, String)]) -> Data {
        var output = Data(); var central = Data(); var offset: UInt32 = 0
        for (name, text) in files {
            let nameData = Data(name.utf8), body = Data(text.utf8), checksum = crc32(body)
            append([
                le(0x04034b50), le(20, 2), le(0, 2), le(0, 2), le(0, 2), le(0, 2),
                le(checksum), le(UInt32(body.count)), le(UInt32(body.count)),
                le(UInt32(nameData.count), 2), le(0, 2), nameData, body
            ], to: &output)
            append([
                le(0x02014b50), le(20, 2), le(20, 2), le(0, 2), le(0, 2), le(0, 2),
                le(0, 2), le(checksum), le(UInt32(body.count)), le(UInt32(body.count)),
                le(UInt32(nameData.count), 2), le(0, 2), le(0, 2), le(0, 2), le(0, 2),
                le(0, 4), le(offset), nameData
            ], to: &central)
            offset = UInt32(output.count)
        }
        append([
            central, le(0x06054b50), le(0, 2), le(0, 2), le(UInt32(files.count), 2),
            le(UInt32(files.count), 2), le(UInt32(central.count)), le(offset), le(0, 2)
        ], to: &output)
        return output
    }
    private static func append(_ parts: [Data], to output: inout Data) {
        for part in parts { output.append(part) }
    }
    private static func le(_ value: UInt32, _ bytes: Int = 4) -> Data { Data((0..<bytes).map { UInt8((value >> (8 * $0)) & 0xff) }) }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 } }
        return crc ^ 0xffffffff
    }
}
