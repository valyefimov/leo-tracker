import Foundation
import XCTest
@testable import LeoTracker

final class ExportServiceTests: XCTestCase {
    func testCSVEscapesQuotesAndCommas() {
        let item = TimeEntry(id: 1, projectID: 1, project: "LeoTracker", task: "Design, \"home\"", startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 90))
        let result = ExportService.csv(entries: [item])
        XCTAssertTrue(result.contains("\"Design, \"\"home\"\"\""))
        XCTAssertTrue(result.contains("Date,Project,Task,Started,Ended,Hours,Duration"))
        XCTAssertTrue(result.contains(",0,"))
    }

    func testCSVExportsQuarterHourUnits() {
        XCTAssertEqual(ExportService.exportHours(15 * 60), "0.25")
        XCTAssertEqual(ExportService.exportHours(30 * 60), "0.5")
        XCTAssertEqual(ExportService.exportHours(45 * 60), "0.75")
        XCTAssertEqual(ExportService.exportHours(60 * 60), "1")
        XCTAssertEqual(ExportService.exportHours(2.27 * 60 * 60), "2.25")
    }
}
