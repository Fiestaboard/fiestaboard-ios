import XCTest
import FiestaBoardKit
import FiestaBoardRender
@testable import FiestaBoardAppState

final class DisplayBadgesTests: XCTestCase {
    private func summary(_ id: String, type: String = "flagship", rows: Int = 6, cols: Int = 22, output: String = "vestaboard",
                         paused: Bool = false, model: String? = nil) throws -> BoardSummary {
        var object: [String: Any] = ["id": id, "name": id, "device_type": type, "rows": rows, "cols": cols,
                                     "is_primary": false, "paused": paused, "schedule_enabled": false, "output": output]
        if let model { object["device_model"] = model }
        return try JSONDecoder().decode(BoardSummary.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func runtime(_ json: String) throws -> BoardRuntimeStatus {
        try JSONDecoder().decode(BoardRuntimeStatus.self, from: Data(json.utf8))
    }

    func testOnlyTheBadgesTheFactsImply() throws {
        XCTAssertEqual(DisplayBadge.make(summary: try summary("k"), runtime: try runtime(#"{"configured":true,"paused":false,"output_status":{"state":"connected"}}"#)), [.connected])
        XCTAssertEqual(DisplayBadge.make(summary: try summary("k", paused: true), runtime: nil), [.paused])
        XCTAssertEqual(DisplayBadge.make(summary: try summary("tv", type: "panel", output: "fiestapanel"),
                                         runtime: try runtime(#"{"configured":true,"output_status":{"state":"connected"}}"#)), [.fiestaPanel, .connected])
        XCTAssertEqual(DisplayBadge.make(summary: try summary("m"), runtime: try runtime(#"{"configured":false,"error":"Output plugin failed","output_status":{"state":"connected"}}"#)), [.unavailable],
                       "an unavailable display is never also Connected")
        XCTAssertEqual(DisplayBadge.make(summary: try summary("q"), runtime: try runtime(#"{"configured":true,"output_status":{"state":"not_configured"}}"#)), [.notConfigured])
        XCTAssertEqual(DisplayBadge.make(summary: try summary("x"), runtime: nil), [], "no facts, no badges")
    }

    func testDescriptionLine() throws {
        let desk = try summary("desk", type: "note", rows: 3, cols: 15)
        let white = DisplayModel(summary: BoardSummaryFields(desk), stored: ["board_color": "white"])
        XCTAssertEqual(DisplayDescription.line(summary: desk, model: white), "Note • 3×15 • White")
        let pixoo = try summary("pixoo", type: "panel", rows: 10, cols: 16, output: "divoom_pixoo", model: "divoom_pixoo64")
        let led = DisplayModel(summary: BoardSummaryFields(pixoo), stored: nil)
        XCTAssertEqual(DisplayDescription.line(summary: pixoo, model: led), "LED 64×64 • 10×16 • Full colour")
        XCTAssertEqual(DisplayDescription.output("divoom_pixoo"), "Divoom Pixoo")
        XCTAssertEqual(DisplayDescription.output("acme_marquee"), "Acme Marquee")
    }
}
