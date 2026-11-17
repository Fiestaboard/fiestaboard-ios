import XCTest
import FiestaBoardKit
import FiestaBoardRender
@testable import FiestaBoardAppState

final class ComposePreviewProjectionTests: XCTestCase {
    private func raw(_ file: String, _ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let bytes = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/Compose/\(file).json"))
        let corpus = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        let response = try XCTUnwrap((corpus["records"] as? [[String: Any]])?.first { $0["case"] as? String == name }?["response"])
        return try JSONSerialization.data(withJSONObject: response)
    }
    func testActualRichTC001PreviewUsesObservedPixelsFontAndMarkupInSharedRenderer() throws {
        let board = try JSONDecoder().decode(BoardDetail.self, from: raw("operations-authenticated", "drawing-tc001-fixture"))
        let preview = try TemplatePreviewResult(rawData: raw("long-led-authenticated", "preview-rich-19"))
        let projection = try ComposePreviewProjection(preview: preview, summary: BoardSummaryFields(board.summary), drawing: board.drawing)
        XCTAssertEqual(projection.model.geometry, .pixels(w: 32, h: 8)); XCTAssertEqual(projection.model.font, .f3x5)
        XCTAssertEqual(projection.frame.message, "{red:ABCDEFGH}")
        let raster = LedRasterizer.raster(projection.frame, model: projection.model)
        XCTAssertEqual(raster.width, 32); XCTAssertEqual(raster.height, 8)
        XCTAssertTrue(raster.pixels.contains(0xeb4034), "Named red uses the audited FiestaUI/backend palette")
        XCTAssertFalse(raster.pixels.contains(0xffffff), "Rich red markup must not become flattened white text")
    }
    func testActualLegacyOverlayIsProjectedIntoBoardViewportFrame() throws {
        let board = try JSONDecoder().decode(BoardDetail.self, from: raw("operations-authenticated", "drawing-tc001-fixture"))
        let preview = try TemplatePreviewResult(rawData: raw("operations-authenticated", "led-canvas-overlay"))
        let projection = try ComposePreviewProjection(preview: preview, summary: BoardSummaryFields(board.summary), drawing: board.drawing)
        XCTAssertEqual(projection.frame.layers.count, 1)
        XCTAssertEqual(projection.frame.layers[0].w, 3); XCTAssertEqual(projection.frame.layers[0].h, 5)
        XCTAssertEqual(projection.frame.layers[0].rgba.prefix(4), Data([255, 0, 0, 255]).prefix(4))
    }
}
