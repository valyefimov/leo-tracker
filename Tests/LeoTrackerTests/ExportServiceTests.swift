import Foundation
import XCTest
@testable import LeoTracker

final class ExportServiceTests: XCTestCase {
    func testCSVEscapesQuotesAndCommas() {
        let item = TimeEntry(id: 1, project: "LeoTracker", task: "Design, \"home\"", startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 90))
        let result = ExportService.csv(entries: [item])
        XCTAssertTrue(result.contains("\"Design, \"\"home\"\"\""))
        XCTAssertTrue(result.contains(",90,"))
    }

    func testExcelCreatesEscapedWorkbookArchive() {
        let item = TimeEntry(id: 1, project: "LeoTracker", task: "API < UI & QA", startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60))
        let workbook = ExportService.xlsx(entries: [item])
        XCTAssertEqual(Array(workbook.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertTrue(String(decoding: workbook, as: UTF8.self).contains("API &lt; UI &amp; QA"))
    }
}
