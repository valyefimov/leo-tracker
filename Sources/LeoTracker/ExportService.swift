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
                escape(exportHours(entry.duration)),
                escape(formatDecimal(entry.projectHourlyRate)),
                escape(exportAmount(duration: entry.duration, hourlyRate: entry.projectHourlyRate)),
                entry.duration.clockText
            ].joined(separator: ",")
        }
        return (["Date,Project,Task,Started,Ended,Hours,Rate/hour,Amount,Duration"] + rows).joined(separator: "\n")
    }

    static func exportHours(_ duration: TimeInterval) -> String {
        formatDecimal(roundedQuarterHours(duration))
    }

    static func roundedQuarterHours(_ duration: TimeInterval) -> Double {
        (max(0, duration) / 3600 / 0.25).rounded() * 0.25
    }

    static func exportAmount(duration: TimeInterval, hourlyRate: Double) -> String {
        formatDecimal(roundedQuarterHours(duration) * max(0, hourlyRate))
    }

    static func formatDecimal(_ value: Double) -> String {
        let roundedValue = (max(0, value) * 100).rounded() / 100
        if roundedValue.rounded() == roundedValue {
            return String(Int(roundedValue))
        }
        if (roundedValue * 10).rounded() == roundedValue * 10 {
            return String(format: "%.1f", roundedValue).replacingOccurrences(of: ".", with: ",")
        }
        return String(format: "%.2f", roundedValue).replacingOccurrences(of: ".", with: ",")
    }

    private static func dateOnly(_ date: Date) -> String { formatted(date, format: "yyyy-MM-dd") }
    private static func csvDate(_ date: Date) -> String { dateOnly(date) }
    private static func formatted(_ date: Date, format: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = format
        return formatter.string(from: date)
    }
    private static func escape(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}
