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

    static func exportUnits(_ duration: TimeInterval) -> Int { Int((duration / 36).rounded()) }

    private static func dateOnly(_ date: Date) -> String { formatted(date, format: "yyyy-MM-dd") }
    private static func csvDate(_ date: Date) -> String { dateOnly(date) }
    private static func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = format
        return formatter.string(from: date)
    }
    private static func escape(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}
