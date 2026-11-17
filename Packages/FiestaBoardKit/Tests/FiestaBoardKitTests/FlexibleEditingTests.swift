import Foundation
import XCTest
@testable import FiestaBoardKit

final class FlexibleEditingTests: XCTestCase {
    func testFlexiblePreviewIsEvaluationAndOnlyExactEndpointIsExempt() {
        XCTAssertFalse(APIRequest(.post, path: ["pages", "preview", "flexible"]).isMutation)
        XCTAssertTrue(APIRequest(.post, path: ["pages", "preview", "flexible", "live"]).isMutation)
        XCTAssertTrue(APIRequest(.put, path: ["pages", "preview", "flexible"]).isMutation)
    }
}

extension FlexibleEditingTests {
    func testSparseFlexiblePatchRetainsExactNumbersNullAndOmissionWithoutGridLeakage() throws {
        let blocks = Data(#"[{"id":"c","kind":"canvas","opaque":null,"canvas":{"content":{"size":[32,16],"shapes":[{"type":"rect","x":0,"y":0,"w":2,"h":2,"opaque":900719925474099312345678}]}}},{"id":"future","kind":"future","large":900719925474099312345678}]"#.utf8)
        let patch = PageSavePatch(blocksData: blocks, styleData: Data("null".utf8), expectedRevision: "original")
        let data = try patch.serializedData()
        let members = try RawJSONObject.members(data)
        XCTAssertEqual(members["blocks"], blocks)
        XCTAssertEqual(members["style"], Data("null".utf8))
        XCTAssertNil(members["layout"]); XCTAssertNil(members["targets"]); XCTAssertNil(members["type"]); XCTAssertNil(members["template"])
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(members["expected_revision"])), "original")
        XCTAssertThrowsError(try PageSavePatch(template: ["A"], blocksData: blocks, expectedRevision: "r").serializedData())
        XCTAssertThrowsError(try PageSavePatch(blocksData: Data("null".utf8), expectedRevision: "r").serializedData())
        XCTAssertThrowsError(try PageSavePatch(blocksData: Data("[]".utf8), expectedRevision: "r").serializedData())
        XCTAssertThrowsError(try JSONEncoder().encode(patch))
    }
    func testFlexiblePreviewUsesDedicatedWireModelSharedSurfaceAndWarnings() throws {
        let data = Data(#"{"available":true,"page_id":"unsaved","message":"A","lines":["A"],"display_type":"panel","raw":{},"layout_issues":[{"path":["blocks","t"],"code":"shrunk","severity":"warning","message":"shrunk"}],"canvas_issues":[],"layers":[{"physical_frame_version":1,"x":0,"y":0,"width":1,"height":1,"rgba":"/wAA/w=="}]}"#.utf8)
        let result = try FlexiblePreviewResult(rawData: data)
        XCTAssertEqual(result.lines, ["A"]); XCTAssertEqual(result.layoutIssueCount, 1)
        XCTAssertEqual(result.canvasIssueCount, 0)
        XCTAssertEqual(result.layoutWarnings, ["shrunk"])
        XCTAssertEqual(result.canvasWarnings, [])
        guard case .physical(let frame) = result.surface else { return XCTFail() }
        XCTAssertEqual(frame.rgba, Data([255, 0, 0, 255]))
        XCTAssertThrowsError(try TemplatePreviewResult(rawData: data))
        XCTAssertThrowsError(try FlexiblePreviewResult(rawData: Data(#"{"available":true,"page_id":"other","message":"A","lines":["A"],"display_type":"panel","raw":{},"layout_issues":[]}"#.utf8)))
    }
}
