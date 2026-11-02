import XCTest
@testable import FiestaBoardKit

/// PLAN B24/§2.4: a legacy page's canvases travel as the raw `canvases` bytes, re-validated.
final class CanvasesPatchTests: XCTestCase {
    func testCanvasesAreSentVerbatim() throws {
        let raw = ##"[{"id":"sun","area":{"row":1,"col":1,"rows":5,"cols":8},"content":{"shapes":[{"type":"rect","x":12,"y":4.0,"w":6,"h":3,"fill":"#ff0000","future":900719925474099312345678}]}}]"##
        let patch = PageSavePatch(template: ["A"], canvasesData: Data(raw.utf8), expectedRevision: "r1")
        // JSONEncoder's key order is unspecified (W4: this compared whole strings and flaked), so
        // compare members: canvases must be the raw bytes, verbatim.
        let members = try RawJSONObject.members(try patch.serializedData())
        XCTAssertEqual(Set(members.keys), ["template", "expected_revision", "canvases"])
        XCTAssertEqual(members["canvases"].map { String(decoding: $0, as: UTF8.self) }, raw)
        XCTAssertEqual(members["template"].map { String(decoding: $0, as: UTF8.self) }, #"["A"]"#)
        // Removing every canvas sends null or [] as stored; canvases alone are a valid patch.
        XCTAssertEqual(String(decoding: try PageSavePatch(canvasesData: Data("null".utf8), expectedRevision: "r1").serializedData(), as: UTF8.self),
                       #"{"expected_revision":"r1","canvases":null}"#)
        XCTAssertNoThrow(try PageSavePatch(canvasesData: Data("[]".utf8), expectedRevision: "r1").serializedData())
    }
    func testMalformedCanvasesAndFlexibleMixesAreRefused() {
        for bad in ["{}", "[1]", #"[{"id":"a","id":"b"}]"#, "[" + Array(repeating: #"{"id":"a"}"#, count: 9).joined(separator: ",") + "]"] {
            XCTAssertThrowsError(try PageSavePatch(canvasesData: Data(bad.utf8), expectedRevision: "r1").serializedData(), bad)
        }
        XCTAssertThrowsError(try PageSavePatch(blocksData: Data("[]".utf8), canvasesData: Data("[]".utf8), expectedRevision: "r1").serializedData())
    }
}
