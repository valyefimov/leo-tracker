import Foundation
import XCTest
@testable import LeoTracker

final class ExportServiceTests: XCTestCase {
    func testCSVEscapesQuotesAndCommas() {
        let item = TimeEntry(id: 1, task: "Design, \"home\"", startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 90))
        let result = ExportService.csv(entries: [item])
        XCTAssertTrue(result.contains("\"Design, \"\"home\"\"\""))
        XCTAssertTrue(result.contains(",90,"))
    }

    func testExcelEscapesXML() {
        let item = TimeEntry(id: 1, task: "API < UI & QA", startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60))
        XCTAssertTrue(ExportService.excelXML(entries: [item]).contains("API &lt; UI &amp; QA"))
    }
}
