import Foundation

enum ExportService {
    static func csv(entries: [TimeEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = entries.map { entry in
            [
                escape(entry.task),
                formatter.string(from: entry.startedAt),
                entry.endedAt.map(formatter.string(from:)) ?? "",
                String(Int(entry.duration)),
                entry.duration.shortText
            ].joined(separator: ",")
        }
        return (["Задача,Начало,Окончание,Секунды,Длительность"] + rows).joined(separator: "\n")
    }

    static func excelXML(entries: [TimeEntry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        let rows = entries.map { entry in
            """
            <Row><Cell><Data ss:Type="String">\(xml(entry.task))</Data></Cell><Cell><Data ss:Type="String">\(formatter.string(from: entry.startedAt))</Data></Cell><Cell><Data ss:Type="String">\(entry.endedAt.map(formatter.string(from:)) ?? "")</Data></Cell><Cell><Data ss:Type="Number">\(Int(entry.duration))</Data></Cell><Cell><Data ss:Type="String">\(entry.duration.shortText)</Data></Cell></Row>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        <Worksheet ss:Name="Отчёт"><Table>
        <Row><Cell><Data ss:Type="String">Задача</Data></Cell><Cell><Data ss:Type="String">Начало</Data></Cell><Cell><Data ss:Type="String">Окончание</Data></Cell><Cell><Data ss:Type="String">Секунды</Data></Cell><Cell><Data ss:Type="String">Длительность</Data></Cell></Row>
        \(rows)
        </Table></Worksheet></Workbook>
        """
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
