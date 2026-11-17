import Foundation
import XCTest
@testable import FiestaBoardKit

final class PhysicalFramePreviewTests: XCTestCase {
    // The physical surface can differ from the board's legacy character geometry.
    func testPhysicalGoldensKeepExactDimensionsLastPixelAndBlack() throws {
        for (width, height) in [(32, 8), (52, 16), (64, 64)] {
            var bytes = Array(repeating: UInt8(0), count: width * height * 4)
            for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
            bytes.replaceSubrange(0..<4, with: [1, 2, 3, 255])
            bytes.replaceSubrange((bytes.count - 4)..<bytes.count, with: [254, 128, 64, 255])
            let result = try TemplatePreviewResult(rawData: reply([layer(width, height, bytes)]))
            guard case .physical(let frame) = result.surface else {
                XCTFail("Explicit physical frame must be available at \(width)×\(height)"); continue
            }
            XCTAssertEqual(frame.width, width)
            XCTAssertEqual(frame.height, height)
            XCTAssertEqual(frame.rgba.count, width * height * 4)
            XCTAssertEqual(Array(frame.rgba.prefix(4)), [1, 2, 3, 255])
            XCTAssertEqual(Array(frame.rgba[4..<8]), [0, 0, 0, 255])
            XCTAssertEqual(Array(frame.rgba.suffix(4)), [254, 128, 64, 255])
            XCTAssertTrue(result.hasLayers)
        }
    }

    func testLegacyLayerNeverBecomesPhysicalBySize() throws {
        var legacy = layer(1, 1, [0, 0, 0, 255])
        legacy.removeValue(forKey: "physical_frame_version")
        let result = try TemplatePreviewResult(rawData: reply([legacy]))
        XCTAssertEqual(result.surface, .legacy)
        XCTAssertTrue(result.hasLayers)
    }

    func testPresentNullMarkerIsUnsupportedRatherThanLegacy() throws {
        var value = layer(1, 1, [0, 0, 0, 255])
        value["physical_frame_version"] = NSNull()
        XCTAssertEqual(try TemplatePreviewResult(rawData: reply([value])).surface, .unsupported)
    }

    func testFuturePhysicalProtocolIsRetainedButNotRendered() throws {
        let raw = try reply([["physical_frame_version": 2, "future": ["value": NSNull()]]])
        let result = try TemplatePreviewResult(rawData: raw)
        XCTAssertEqual(result.surface, .unsupported)
        XCTAssertEqual(result.rawData, raw)
    }

    func testMalformedPhysicalFramesAreRejectedWithoutGuessingGeometry() throws {
        let valid = layer(1, 1, [0, 0, 0, 255])
        let changes: [[String: Any]] = [
            ["width": 0], ["width": 513], ["height": -1], ["height": 513],
            ["width": Int.max], ["height": Int.max], ["width": UInt64.max],
            ["width": 1.5], ["x": 1], ["y": -1], ["rgba": "!"],
            ["rgba": Data([0, 0, 0]).base64EncodedString()],
            ["rgba": Data([0, 0, 0, 0]).base64EncodedString()],
        ]
        for change in changes {
            XCTAssertThrowsError(try TemplatePreviewResult(rawData: reply([valid.merging(change) { _, new in new }])))
        }
        XCTAssertThrowsError(try TemplatePreviewResult(rawData: reply([valid, valid])))
    }

    func testUnknownMarkerCannotFallBackToKnownFrame() throws {
        let result = try TemplatePreviewResult(rawData: reply([
            layer(1, 1, [0, 0, 0, 255]), ["physical_frame_version": "future"]
        ]))
        XCTAssertEqual(result.surface, .unsupported)
    }

    private func layer(_ width: Int, _ height: Int, _ rgba: [UInt8]) -> [String: Any] {
        ["physical_frame_version": 1, "x": 0, "y": 0, "width": width, "height": height,
         "rgba": Data(rgba).base64EncodedString()]
    }
    private func reply(_ layers: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "rendered": "", "lines": [""], "line_count": 1, "charset": "ascii",
            "charset_issues": [], "canvas_issues": [], "layers": layers,
            "grid_rows": 6, "grid_cols": 22
        ] as [String: Any])
    }
}
