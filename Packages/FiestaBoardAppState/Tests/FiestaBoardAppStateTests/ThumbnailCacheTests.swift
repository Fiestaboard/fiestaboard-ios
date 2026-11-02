import XCTest
import FiestaBoardKit
import FiestaBoardRender
@testable import FiestaBoardAppState

final class ThumbnailCacheTests: XCTestCase {
    private func page(_ id: String, revision: String?, type: String = "template", device: String? = "flagship",
                      extra: [String: Any] = [:]) throws -> Page {
        var object: [String: Any] = ["id": id, "name": id, "type": type, "template": ["HI"]]
        if let revision { object["revision"] = revision }
        if let device { object["device_type"] = device }
        object.merge(extra) { _, new in new }
        return try JSONDecoder().decode(Page.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func preview(_ id: String, _ line: String) -> PagePreview {
        PagePreview(pageID: id, available: true, lines: [line], displayType: "flagship", cellsJSON: nil, layers: [], error: nil)
    }

    /// B11: a thumbnail is reused until the page changes (its revision — the
    /// server bumps it on every save, as `updated_at`), or the display changes.
    func testKeyedOnUpdatedAt() throws {
        var cache = ThumbnailCache()
        let v1 = try page("a", revision: "r1")
        cache.store(preview("a", "ONE"), for: ThumbnailKey(page: v1, boardID: "kitchen"))
        XCTAssertEqual(cache.preview(for: ThumbnailKey(page: try page("a", revision: "r1"), boardID: "kitchen"))?.lines, ["ONE"])
        let v2 = try page("a", revision: "r2")
        XCTAssertNil(cache.preview(for: ThumbnailKey(page: v2, boardID: "kitchen")), "a saved page re-renders")
        XCTAssertNil(cache.preview(for: ThumbnailKey(page: v1, boardID: "hall")), "another display re-renders")
        cache.store(preview("a", "TWO"), for: ThumbnailKey(page: v2, boardID: "kitchen"))
        XCTAssertEqual(cache.count, 1, "the old revision is dropped")
        XCTAssertEqual(cache.missing([ThumbnailKey(page: v2, boardID: "kitchen"), ThumbnailKey(page: v1, boardID: "hall")]).map(\.boardID), ["hall"])
    }

    func testRevisionlessPagesKeyOnContent() throws {
        let a = try page("a", revision: nil)
        let b = try page("a", revision: nil, extra: ["template": ["BYE"]])
        XCTAssertEqual(ThumbnailKey(page: a, boardID: nil), ThumbnailKey(page: try page("a", revision: nil), boardID: nil))
        XCTAssertNotEqual(ThumbnailKey(page: a, boardID: nil), ThumbnailKey(page: b, boardID: nil))
    }

    func testGeometryLabelsAndFit() throws {
        let note = try XCTUnwrap(PageGeometry(try page("n", revision: "1", device: "note")))
        XCTAssertEqual([note.label, "\(note.rows)x\(note.cols)"], ["Note", "3x15"])
        let wall = try XCTUnwrap(PageGeometry(try page("w", revision: "1", device: "note_array", extra: ["notes_wide": 2, "notes_tall": 2])))
        XCTAssertEqual([wall.label, "\(wall.rows)x\(wall.cols)"], ["Note Array", "6x30"])
        let panel = try XCTUnwrap(PageGeometry(try page("p", revision: "1", device: "panel", extra: ["grid_rows": 12, "grid_cols": 29])))
        XCTAssertEqual(panel.label, "Panel")
        XCTAssertTrue(PageGeometry(try page("f", revision: "1"))!.fits(.flap(rows: 6, cols: 22)))
        XCTAssertFalse(note.fits(.flap(rows: 6, cols: 22)))
        XCTAssertNotNil(PageGeometry(try page("s", revision: nil, type: "single", device: nil)), "single pages still get a thumbnail")
        XCTAssertNil(PageGeometry(try page("x", revision: nil, type: "flexible", device: nil)))
    }

    func testBatchDecodeKeepsErrorsPerPage() throws {
        let data = Data(#"{"previews":{"a":{"available":true,"page_id":"a","message":"HI","lines":["HI","{63}"],"display_type":"flagship","raw":{}},"b":{"available":false,"error":"Template error"}},"total":2,"successful":1}"#.utf8)
        let batch = try PagePreview.decodeBatch(data)
        XCTAssertEqual(batch["a"]?.lines, ["HI", "{63}"])
        XCTAssertEqual(batch["b"]?.available, false)
        XCTAssertEqual(batch["b"]?.error, "Template error")
    }
}
