import Foundation
import XCTest
@testable import LeoTracker

final class ExportServiceTests: XCTestCase {
    func testCSVEscapesQuotesAndCommas() {
        let item = TimeEntry(id: 1, project: "LeoTracker", task: "Design, \"home\"", startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 90))
        let result = ExportService.csv(entries: [item])
        XCTAssertTrue(result.contains("\"Design, \"\"home\"\"\""))
        XCTAssertTrue(result.contains(",3,"))
    }

}
