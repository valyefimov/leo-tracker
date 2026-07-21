import Foundation

struct TimeEntry: Identifiable, Hashable, Sendable {
    let id: Int64
    var project: String
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
