import Foundation
import XCTest
@testable import LeoTracker

final class ProjectDatabaseTests: XCTestCase {
    func testProjectRenameUpdatesFetchedEntries() throws {
        let database = try makeDatabase()
        let project = try database.insertProject(name: "Client A", hourlyRate: 120)
        _ = try database.insert(projectID: project.id, task: "Planning", startedAt: Date(timeIntervalSince1970: 0))

        try database.updateProject(id: project.id, name: "Client B", hourlyRate: 150)

        let entries = try database.fetch()
        XCTAssertEqual(entries.first?.project, "Client B")
        XCTAssertEqual(entries.first?.projectID, project.id)
        XCTAssertEqual(entries.first?.projectHourlyRate, 150)
    }

    func testProjectDeleteReassignsEntries() throws {
        let database = try makeDatabase()
        let fallback = try database.insertProject(name: "Fallback")
        let project = try database.insertProject(name: "Remove Me")
        _ = try database.insert(projectID: project.id, task: "Build", startedAt: Date(timeIntervalSince1970: 0))

        try database.deleteProject(id: project.id, fallbackProjectID: fallback.id)

        let entries = try database.fetch()
        XCTAssertEqual(entries.first?.projectID, fallback.id)
        XCTAssertEqual(entries.first?.project, "Fallback")
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

    private func makeDatabase() throws -> Database {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try Database(path: directory.appendingPathComponent("tracker.sqlite").path)
    }
}
