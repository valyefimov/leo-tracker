import Foundation
import XCTest
@testable import LeoTracker

final class ProjectDatabaseTests: XCTestCase {
    func testProjectRenameUpdatesFetchedEntries() throws {
        let database = try makeDatabase()
        let project = try database.insertProject(name: "Client A", hourlyRate: 120, currency: "usd")
        _ = try database.insert(projectID: project.id, task: "Planning", startedAt: Date(timeIntervalSince1970: 0))

        try database.updateProject(id: project.id, name: "Client B", hourlyRate: 150, currency: "eur")

        let entries = try database.fetch()
        XCTAssertEqual(entries.first?.project, "Client B")
        XCTAssertEqual(entries.first?.projectID, project.id)
        XCTAssertEqual(entries.first?.projectHourlyRate, 150)
        XCTAssertEqual(entries.first?.projectCurrency, "EUR")
    }

    func testProjectDeleteRemovesEntries() throws {
        let database = try makeDatabase()
        _ = try database.insertProject(name: "Fallback")
        let project = try database.insertProject(name: "Remove Me")
        _ = try database.insert(projectID: project.id, task: "Build", startedAt: Date(timeIntervalSince1970: 0))

        try database.deleteProject(id: project.id)

        let entries = try database.fetch()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertFalse(try database.fetchProjects().contains(project))
    }

    func testExportColumnsPersistInDatabase() throws {
        let database = try makeDatabase()

        try database.saveExportColumns([.project, .hours, .amount])

        XCTAssertEqual(try database.fetchExportColumns(), [.project, .hours, .amount])
    }

    func testDefaultProjectPersistsInDatabase() throws {
        let database = try makeDatabase()
        let project = try database.insertProject(name: "Default")

        try database.saveDefaultProjectID(project.id)

        XCTAssertEqual(try database.fetchDefaultProjectID(), project.id)
    }

    func testFetchCanFilterEntriesByProjectInDatabase() throws {
        let database = try makeDatabase()
        let first = try database.insertProject(name: "First")
        let second = try database.insertProject(name: "Second")
        _ = try database.insert(projectID: first.id, task: "A", startedAt: Date(timeIntervalSince1970: 0))
        _ = try database.insert(projectID: second.id, task: "B", startedAt: Date(timeIntervalSince1970: 10))

        let entries = try database.fetch(projectID: second.id)

        XCTAssertEqual(entries.map(\.task), ["B"])
        XCTAssertEqual(entries.first?.projectID, second.id)
    }

    func testBackupExportImportRestoresAllData() throws {
        let source = try makeDatabase()
        let project = try source.insertProject(name: "Client", hourlyRate: 125, currency: "USD")
        _ = try source.insert(projectID: project.id, task: "Work", startedAt: Date(timeIntervalSince1970: 100))
        try source.saveDefaultProjectID(project.id)
        try source.saveExportColumns([.project, .hours, .amount])

        let backup = try source.exportBackup()
        let target = try makeDatabase()
        try target.importBackup(backup)

        let projects = try target.fetchProjects()
        XCTAssertEqual(projects.map(\.name), ["Client", "General"])
        XCTAssertEqual(projects.first(where: { $0.name == "Client" })?.currency, "USD")
        XCTAssertEqual(try target.fetch().map(\.task), ["Work"])
        XCTAssertEqual(try target.fetchDefaultProjectID(), project.id)
        XCTAssertEqual(try target.fetchExportColumns(), [.project, .hours, .amount])
    }

    private func makeDatabase() throws -> Database {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try Database(path: directory.appendingPathComponent("tracker.sqlite").path)
    }
}
