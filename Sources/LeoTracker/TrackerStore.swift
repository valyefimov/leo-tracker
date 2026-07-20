import AppKit
import Combine
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@MainActor
final class TrackerStore: ObservableObject {
    @Published var task = ""
    @Published private(set) var entries: [TimeEntry] = []
    @Published private(set) var projects: [Project] = []
    @Published var selectedProjectID: Int64?
    @Published private(set) var activeEntry: TimeEntry?
    @Published private(set) var now = Date()
    @Published var range: ReportRange = .week { didSet { reload() } }
    @Published var errorMessage: String?
    @Published var autoStopMessage: String?

    let idleLimit: TimeInterval = 5 * 60
    private let database: Database
    private var timer: Timer?

    init() {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LeoTracker", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            database = try Database(path: support.appendingPathComponent("tracker.sqlite").path)
            let all = try database.fetch()
            if let unfinished = all.first(where: { $0.endedAt == nil }) {
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
            let project = projects.first(where: { $0.id == projectID })?.name ?? "General"
            activeEntry = TimeEntry(id: id, project: project, task: cleanTask, startedAt: date, endedAt: nil)
            now = date
            autoStopMessage = nil
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func stop(automatic: Bool = false) {
        guard let activeEntry else { return }
        do {
            let date = Date()
            try database.stop(id: activeEntry.id, endedAt: date)
            self.activeEntry = nil
            task = ""
            if automatic { autoStopMessage = "Timer stopped after 5 minutes of inactivity." }
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(entry: TimeEntry) {
        guard entry.id != activeEntry?.id else { errorMessage = "Stop the active session before deleting it."; return }
        do { try database.deleteEntry(id: entry.id); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func createProject(named name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        do {
            let project = try database.insertProject(name: cleanName)
            projects = try database.fetchProjects()
            selectedProjectID = project.id
        } catch { errorMessage = "Could not create project: \(error.localizedDescription)" }
    }

    func exportCSV() { save(data: Data(("\u{FEFF}" + ExportService.csv(entries: entries)).utf8), name: "leo-report.csv", type: "csv") }
    func exportExcel() { save(data: ExportService.xlsx(entries: entries), name: "leo-report.xlsx", type: "xlsx") }

    private func tick() {
        now = Date()
        guard isTracking, systemIdleTime >= idleLimit else { return }
        stop(automatic: true)
    }

    private var systemIdleTime: TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private func reload() {
        do {
            projects = try database.fetchProjects()
            if selectedProjectID == nil || !projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = projects.first?.id
            }
            entries = try database.fetch(from: range.startDate())
        }
        catch { errorMessage = error.localizedDescription }
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
