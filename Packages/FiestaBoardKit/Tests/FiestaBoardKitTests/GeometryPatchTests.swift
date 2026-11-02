import XCTest
@testable import FiestaBoardKit

/// PLAN B20/§2.4: a board-shape change travels as raw `device_type` / `notes_*` / `grid_*` members.
final class GeometryPatchTests: XCTestCase {
    func testGeometryMembersAreSentVerbatim() throws {
        let patch = PageSavePatch(geometryData: ["device_type": Data(#""note_array""#.utf8), "notes_wide": Data("2".utf8), "notes_tall": Data("1".utf8)],
                                  expectedRevision: "r1")
        let text = String(decoding: try patch.serializedData(), as: UTF8.self)
        XCTAssertEqual(text, #"{"expected_revision":"r1","device_type":"note_array","notes_wide":2,"notes_tall":1}"#)
    }
    func testUnknownGeometryKeysAndFlexibleMixesAreRefused() {
        XCTAssertThrowsError(try PageSavePatch(geometryData: ["rows": Data("3".utf8)], expectedRevision: "r1").serializedData())
        XCTAssertThrowsError(try PageSavePatch(blocksData: Data("[]".utf8), geometryData: ["device_type": Data(#""note""#.utf8)], expectedRevision: "r1").serializedData())
    }
}
