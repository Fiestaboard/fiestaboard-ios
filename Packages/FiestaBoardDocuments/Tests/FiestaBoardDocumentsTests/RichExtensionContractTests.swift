import Foundation
import XCTest
@testable import FiestaBoardDocuments

final class RichExtensionContractTests: XCTestCase {
    func testNestedCanvasReplacementPreservesUnknownNumbersNullsAndOmission() throws {
        let fixture = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "rich-extensions-v1", withExtension: "json", subdirectory: "Fixtures")))
        guard case .object(let envelope) = try LosslessJSON.parse(fixture),
              case .array(let pages) = envelope["pages"], case .object(var page) = pages.first,
              case .array(var canvases) = page["canvases"], case .object(var canvas) = canvases.first,
              case .object(var content) = canvas["content"], case .array(var shapes) = content["shapes"],
              case .object(var shape) = shapes.first else { return XCTFail("Invalid golden fixture") }
        let originalPage = page
        let originalShape = shape
        shape["x"] = .number("7")
        shapes[0] = .object(shape); content["shapes"] = .array(shapes)
        canvas["content"] = .object(content); canvases[0] = .object(canvas)
        page["canvases"] = .array(canvases)
        page["revision"] = .string("original-r1")
        let encoded = try LosslessJSON.object(page).serializedData()
        guard case .object(let reopened) = try LosslessJSON.parse(encoded),
              case .array(let reopenedCanvases) = reopened["canvases"], case .object(let reopenedCanvas) = reopenedCanvases[0],
              case .object(let reopenedContent) = reopenedCanvas["content"], case .array(let reopenedShapes) = reopenedContent["shapes"],
              case .object(let reopenedShape) = reopenedShapes[0], case .object(let future) = reopenedShape["future_shape"] else {
            return XCTFail("Replacement lost structure")
        }
        XCTAssertEqual(reopened["revision"], .string("original-r1"))
        XCTAssertEqual(reopened["future_page"], originalPage["future_page"])
        XCTAssertEqual(reopenedCanvas["source"], .null)
        XCTAssertNil(reopenedCanvas["unmentioned"])
        XCTAssertEqual(reopenedContent["background"], .null)
        XCTAssertEqual(reopenedShape["stroke"], .null)
        XCTAssertEqual(reopenedShape["x"], .number("7"))
        XCTAssertEqual(reopenedShape["future_shape"], originalShape["future_shape"])
        XCTAssertEqual(future["number"], .number("900719925474099312345678"))
        XCTAssertEqual(future["nullable"], .null)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("1e+100"))
    }
}
