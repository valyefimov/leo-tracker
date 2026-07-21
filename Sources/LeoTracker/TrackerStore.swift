import AppKit
import Combine
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@MainActor
final class TrackerStore: ObservableObject {
    @Published var task = ""
    @Published private(set) var entries: [TimeEntry] = []
    @Published private(set) var reportEntries: [TimeEntry] = []
    @Published private(set) var projects: [Project] = []
    @Published var selectedProjectID: Int64?
    @Published private(set) var defaultProjectID: Int64?
    @Published var reportProjectID: Int64? {
        didSet {
            if oldValue != reportProjectID { reloadReport() }
        }
    }
    @Published private(set) var activeEntry: TimeEntry?
    @Published private(set) var now = Date()
    @Published var range: ReportRange = .week { didSet { reload() } }
    @Published var errorMessage: String?
    @Published var autoStopMessage: String?
    @Published private(set) var exportColumns: [ExportColumn] = ExportColumn.allCases
    @Published var autoStopMinutes: Int {
        didSet { UserDefaults.standard.set(autoStopMinutes, forKey: Self.autoStopMinutesKey) }
    }

    private static let autoStopMinutesKey = "autoStopMinutes"
    private let database: Database
    private var timer: Timer?

    init() {
        do {
            autoStopMinutes = UserDefaults.standard.object(forKey: Self.autoStopMinutesKey) as? Int ?? 5
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LeoTracker", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            database = try Database(path: support.appendingPathComponent("tracker.sqlite").path)
            exportColumns = try database.fetchExportColumns()
            defaultProjectID = try database.fetchDefaultProjectID()
            if let unfinished = try database.fetchUnfinishedEntry() {
                try database.stop(id: unfinished.id, endedAt: Date())
            }
        } catch {
            fatalError(error.localizedDescription)
        }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var isTracking: Bool { activeEntry != nil }
    var elapsed: TimeInterval { activeEntry.map { now.timeIntervalSince($0.startedAt) } ?? 0 }
    var totalDuration: TimeInterval { entries.reduce(0) { $0 + $1.duration } }
    var totalReportDuration: TimeInterval { reportEntries.reduce(0) { $0 + $1.duration } }
    var totalReportAmount: Double {
        reportEntries.reduce(0) { $0 + ExportService.roundedQuarterHours($1.duration) * $1.projectHourlyRate }
    }
    var reportCurrency: String {
        projects.first(where: { $0.id == reportProjectID })?.currency
            ?? reportEntries.first?.projectCurrency
            ?? "EUR"
    }
    var idleLimit: TimeInterval? { autoStopMinutes > 0 ? TimeInterval(autoStopMinutes * 60) : nil }
    var autoStopDescription: String { autoStopMinutes > 0 ? "Auto-stops after \(autoStopMinutes) minutes inactive" : "Auto-stop is off" }

    func toggleTracking() {
        isTracking ? stop() : start()
    }

    func start() {
        let cleanTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTask.isEmpty else {
            errorMessage = "Enter a task before starting the timer."
            return
        }
        guard let projectID = selectedProjectID else {
            errorMessage = "Create or select a project first."
            return
        }
        do {
            let date = Date()
            let id = try database.insert(projectID: projectID, task: cleanTask, startedAt: date)
            let project = projects.first(where: { $0.id == projectID })
            activeEntry = TimeEntry(
                id: id,
                projectID: projectID,
                project: project?.name ?? "General",
                projectHourlyRate: project?.hourlyRate ?? 0,
                projectCurrency: project?.currency ?? "EUR",
                task: cleanTask,
                startedAt: date,
                endedAt: nil
            )
            now = date
            autoStopMessage = nil
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func continueSession(from entry: TimeEntry) {
        guard !isTracking else {
            errorMessage = "Stop the active session before continuing another one."
            return
        }
        task = entry.task
        selectedProjectID = entry.projectID
        start()
    }

    func stop(automatic: Bool = false) {
        guard let activeEntry else { return }
        do {
            let date = Date()
            try database.stop(id: activeEntry.id, endedAt: date)
            self.activeEntry = nil
            task = ""
            if automatic { autoStopMessage = "Timer stopped after \(autoStopMinutes) minutes of inactivity." }
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(entry: TimeEntry) {
        guard entry.id != activeEntry?.id else { errorMessage = "Stop the active session before deleting it."; return }
        do { try database.deleteEntry(id: entry.id); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func update(entry: TimeEntry, task: String, startedAt: Date, endedAt: Date?) {
        let cleanTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTask.isEmpty else {
            errorMessage = "Session name cannot be empty."
            return
        }
        if let endedAt, endedAt < startedAt {
            errorMessage = "End time must be after start time."
            return
        }
        do {
            try database.updateEntry(id: entry.id, task: cleanTask, startedAt: startedAt, endedAt: endedAt)
            if activeEntry?.id == entry.id {
                activeEntry = TimeEntry(
                    id: entry.id,
                    projectID: entry.projectID,
                    project: entry.project,
                    projectHourlyRate: entry.projectHourlyRate,
                    projectCurrency: entry.projectCurrency,
                    task: cleanTask,
                    startedAt: startedAt,
                    endedAt: endedAt
                )
                self.task = cleanTask
            }
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func createProject(named name: String, hourlyRate: Double = 0, currency: String = "EUR") {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        do {
            let project = try database.insertProject(name: cleanName, hourlyRate: hourlyRate, currency: currency)
            projects = try database.fetchProjects()
            selectedProjectID = project.id
            if defaultProjectID == nil { setDefaultProject(id: project.id) }
            reportProjectID = project.id
        } catch { errorMessage = "Could not create project: \(error.localizedDescription)" }
    }

    func update(project: Project, name: String, hourlyRate: Double, currency: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorMessage = "Project name cannot be empty."
            return false
        }
        guard hourlyRate >= 0 else {
            errorMessage = "Rate per hour cannot be negative."
            return false
        }
        do {
            try database.updateProject(id: project.id, name: cleanName, hourlyRate: hourlyRate, currency: currency)
            reload()
            return true
        } catch {
            errorMessage = "Could not update project: \(error.localizedDescription)"
            return false
        }
    }

    func delete(project: Project) {
        guard projects.count > 1 else {
            errorMessage = "Create another project before deleting this one."
            return
        }
        guard activeEntry?.projectID != project.id else {
            errorMessage = "Stop the active session before deleting its project."
            return
        }
        guard let fallbackProjectID = projects.first(where: { $0.id != project.id })?.id else { return }
        do {
            try database.deleteProject(id: project.id)
            if selectedProjectID == project.id { selectedProjectID = fallbackProjectID }
            if reportProjectID == project.id { reportProjectID = fallbackProjectID }
            if defaultProjectID == project.id { setDefaultProject(id: fallbackProjectID) }
            reload()
        } catch { errorMessage = "Could not delete project: \(error.localizedDescription)" }
    }

    func setDefaultProject(id projectID: Int64?) {
        guard let projectID, projects.contains(where: { $0.id == projectID }) else {
            errorMessage = "Select a valid default project."
            return
        }
        do {
            try database.saveDefaultProjectID(projectID)
            defaultProjectID = projectID
            if !isTracking { selectedProjectID = projectID }
        } catch { errorMessage = "Could not save default project: \(error.localizedDescription)" }
    }

    func setExportColumn(_ column: ExportColumn, isEnabled: Bool) {
        var selected = exportColumns
        if isEnabled {
            if !selected.contains(column) { selected.append(column) }
        } else {
            selected.removeAll { $0 == column }
        }
        selected = ExportColumn.allCases.filter { selected.contains($0) }
        guard !selected.isEmpty else {
            errorMessage = "Select at least one export column."
            return
        }
        do {
            try database.saveExportColumns(selected)
            exportColumns = selected
        } catch { errorMessage = "Could not save export settings: \(error.localizedDescription)" }
    }

    func exportCSV(entries: [TimeEntry]) { save(data: Data(("\u{FEFF}" + ExportService.csv(entries: entries, columns: exportColumns)).utf8), name: "leo-report.csv", type: "csv") }

    func exportAllData() {
        do {
            let backup = try database.exportBackup()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(backup)
            save(data: data, name: "leo-tracker-backup.json", type: "json")
        } catch { errorMessage = "Could not export backup: \(error.localizedDescription)" }
    }

    func importAllData() {
        guard !isTracking else {
            errorMessage = "Stop the active session before importing a backup."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(LeoTrackerBackup.self, from: data)
            guard backup.version == 1 else {
                errorMessage = "Unsupported backup version: \(backup.version)."
                return
            }
            try database.importBackup(backup)
            exportColumns = try database.fetchExportColumns()
            defaultProjectID = try database.fetchDefaultProjectID()
            activeEntry = nil
            task = ""
            reload()
        } catch { errorMessage = "Could not import backup: \(error.localizedDescription)" }
    }

    private func tick() {
        now = Date()
        guard let idleLimit, isTracking, systemIdleTime >= idleLimit else { return }
        stop(automatic: true)
    }

    private var systemIdleTime: TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private func reload() {
        do {
            projects = try database.fetchProjects()
            if defaultProjectID == nil || !projects.contains(where: { $0.id == defaultProjectID }) {
                if let firstProjectID = projects.first?.id {
                    try database.saveDefaultProjectID(firstProjectID)
                    defaultProjectID = firstProjectID
                }
            }
            if selectedProjectID == nil || !projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = defaultProjectID ?? projects.first?.id
            }
            if reportProjectID == nil || !projects.contains(where: { $0.id == reportProjectID }) {
                reportProjectID = selectedProjectID ?? projects.first?.id
            }
            entries = try database.fetch(from: range.startDate())
            reloadReport()
        }
        catch { errorMessage = error.localizedDescription }
    }

    private func reloadReport() {
        do {
            reportEntries = try database.fetch(from: range.startDate(), projectID: reportProjectID)
        } catch { errorMessage = error.localizedDescription }
    }

    private func save(data: Data, name: String, type: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        guard let contentType = UTType(filenameExtension: type) else {
            errorMessage = "Unknown export format."
            return
        }
        panel.allowedContentTypes = [contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { errorMessage = "Could not save file: \(error.localizedDescription)" }
    }
}
