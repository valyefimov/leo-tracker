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

    private func makeDatabase() throws -> Database {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try Database(path: directory.appendingPathComponent("tracker.sqlite").path)
    }
}
