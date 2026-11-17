import XCTest
@testable import FiestaBoardKit

final class ComposeDrawingTests: XCTestCase {
    private func response(_ file: String, _ name: String) throws -> [String: Any] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let bytes = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Compose/\(file).json"))
        let corpus = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        let record = try XCTUnwrap((corpus["records"] as? [[String: Any]])?.first { $0["case"] as? String == name })
        return try XCTUnwrap(record["response"] as? [String: Any])
    }
    func testActualDeviceDrawingFactsFilterRichToolsAndIconAllowlist() throws {
        let bytes = try JSONSerialization.data(withJSONObject: response("operations-authenticated", "drawing-tc001-fixture"))
        let board = try JSONDecoder().decode(BoardDetail.self, from: bytes)
        let drawing = try XCTUnwrap(board.drawing)
        XCTAssertEqual(drawing.technology, "led_matrix"); XCTAssertEqual(drawing.font, "3x5")
        XCTAssertEqual(drawing.pixelWidth, 32); XCTAssertEqual(drawing.pixelHeight, 8)
        XCTAssertTrue(drawing.allowsTextColor); XCTAssertTrue(drawing.allowsTiles)
        XCTAssertTrue(drawing.allowedIcons.contains("sun")); XCTAssertFalse(drawing.allowedIcons.contains("cake"))
        let flap = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: response("operations-authenticated", "drawing-hall-1")))
        XCTAssertFalse(flap.drawing?.allowsTextColor ?? true)
        XCTAssertEqual(flap.drawing?.allowedIcons, [])
        XCTAssertTrue(flap.drawing?.allowsTiles == true)
    }
    func testBaselineOrUnknownDrawingCannotAdvertiseRichToolsEvenWithOptimisticFlags() throws {
        let original = try response("operations-authenticated", "drawing-tc001-fixture")
        for source in ["baseline", "future-source"] {
            var board = original, drawing = original["drawing"] as! [String: Any]
            drawing["source"] = source; board["drawing"] = drawing
            let decoded = try JSONDecoder().decode(BoardDetail.self, from: JSONSerialization.data(withJSONObject: board))
            XCTAssertFalse(decoded.drawing?.allowsTextColor ?? true)
            XCTAssertFalse(decoded.drawing?.allowsTiles ?? true)
            XCTAssertEqual(decoded.drawing?.allowedIcons, [])
        }
    }
    func testActualLongRichPreviewRetainsMarkupAndReportsClippingWithoutInventedMarquee() throws {
        let raw = try JSONSerialization.data(withJSONObject: response("long-led-authenticated", "preview-rich-19"))
        let result = try TemplatePreviewResult(rawData: raw)
        XCTAssertEqual(result.rendered, "{red:ABCDEFGH}")
        if case .legacy = result.surface {} else { XCTFail("Current audited wire is legacy markup, without a physical-frame-v1 field") }
        let facts = try ComposePreviewDiagnostics(rawData: raw)
        XCTAssertTrue(facts.hasClippedContent); XCTAssertEqual(facts.maximumSourceWidth, 19)
        XCTAssertEqual(facts.clippedLineNumbers, [1])
    }
    func testActualCanvasOverlaySurvivesFullPreviewDecode() throws {
        let raw = try JSONSerialization.data(withJSONObject: response("operations-authenticated", "led-canvas-overlay"))
        let preview = try TemplatePreviewResult(rawData: raw)
        XCTAssertEqual(preview.layers.count, 1)
        XCTAssertEqual(Data(base64Encoded: preview.layers[0].rgba)?.prefix(4), Data([255, 0, 0, 255]).prefix(4))
    }
}
