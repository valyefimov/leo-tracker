import Foundation

struct TimeEntry: Identifiable, Hashable, Sendable {
    let id: Int64
    var projectID: Int64
    var project: String
    var projectHourlyRate: Double
    var projectCurrency: String
    var task: String
    var startedAt: Date
    var endedAt: Date?

    var duration: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }
}

struct Project: Identifiable, Hashable, Sendable {
    let id: Int64
    var name: String
    var hourlyRate: Double
    var currency: String
}

enum ExportColumn: String, CaseIterable, Identifiable, Sendable {
    case date
    case project
    case task
    case started
    case ended
    case hours
    case rate
    case currency
    case amount
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: "Date"
        case .project: "Project"
        case .task: "Task"
        case .started: "Started"
        case .ended: "Ended"
        case .hours: "Hours"
        case .rate: "Rate/hour"
        case .currency: "Currency"
        case .amount: "Amount"
        case .duration: "Duration"
        }
    }
}

enum ReportRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case all = "All Time"

    var id: Self { self }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .week: return calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .month: return calendar.dateInterval(of: .month, for: now)?.start
        case .all: return nil
        }
    }
}

extension TimeInterval {
    var clockText: String {
        let total = max(0, Int(self))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    var shortText: String {
        let totalMinutes = max(0, Int(self) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var hoursText: String {
        String(format: "%.2f h", max(0, self) / 3600)
    }
}

extension Double {
    var moneyText: String {
        String(format: "%.2f", self).replacingOccurrences(of: ".", with: ",")
    }
}

struct LeoTrackerBackup: Codable, Sendable {
    var version: Int
    var exportedAt: Date
    var projects: [BackupProject]
    var entries: [BackupTimeEntry]
    var settings: [BackupSetting]
}

struct BackupProject: Codable, Sendable {
    var id: Int64
    var name: String
    var hourlyRate: Double
    var currency: String?
}

struct BackupTimeEntry: Codable, Sendable {
    var id: Int64
    var projectID: Int64
    var task: String
    var startedAt: Date
    var endedAt: Date?
}

struct BackupSetting: Codable, Sendable {
    var key: String
    var value: String
}
