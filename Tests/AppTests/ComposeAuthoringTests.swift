import XCTest
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardKit
@testable import FiestaBoard

final class ComposeAuthoringTests: XCTestCase {
    // A replacement that uses Character offsets instead of UTF-16 corrupts emoji selections.
    func testTokenInsertionReplacesSelectedSourceAndRetainsDurationSilenceAndLineFormatting() {
        let input = ComposeInput(text: "Hi 🌮\nSam", lineMetadata: [.init(alignment: "center"), .init(alignment: "right")],
            selection: .init(lowerUTF16: 3, upperUTF16: 5), duration: .minutes(15), silence: .override)
        let edited = ComposeAuthoring.inserting("{{icon.sun}}", into: input)
        XCTAssertEqual(edited.text, "Hi {{icon.sun}}\nSam")
        XCTAssertEqual(edited.selection, .init(lowerUTF16: 15, upperUTF16: 15))
        XCTAssertEqual(edited.lineMetadata.map(\.alignment), ["center", "right"])
        XCTAssertEqual(edited.duration, .minutes(15)); XCTAssertEqual(edited.silence, .override)
    }

    // Rebuilding every line's metadata on a keystroke would lose deliberate formatting.
    func testTextEditPreservesExistingLineMetadataAndClampsSelection() {
        let input = ComposeInput(text: "one\ntwo", lineMetadata: [.init(alignment: "center", wrap: true), .init(alignment: "right")],
            selection: .init(lowerUTF16: 7, upperUTF16: 7), duration: .untilCancel, silence: .hold)
        let edited = ComposeAuthoring.replacingText("one\ntwo\nthree", in: input, selection: .init(lowerUTF16: 99, upperUTF16: 99))
        XCTAssertEqual(edited.lineMetadata, [.init(alignment: "center", wrap: true), .init(alignment: "right"), .init()])
        XCTAssertEqual(edited.selection, .init(lowerUTF16: 13, upperUTF16: 13))
        XCTAssertEqual(edited.duration, .untilCancel); XCTAssertEqual(edited.silence, .hold)
    }

    // A friendly device name must never grant unsupported toolbar operations.
    func testCapabilityToolbarUsesVerifiedH3FactsAndFiltersUnsupportedIcons() throws {
        let baseline = try drawing(source: "baseline")
        XCTAssertEqual(ComposeTools(drawing: baseline).icons, [])
        XCTAssertFalse(ComposeTools(drawing: baseline).textColor)
        XCTAssertFalse(ComposeTools(drawing: baseline).tiles)
        let device = ComposeTools(drawing: try drawing(source: "device"))
        XCTAssertTrue(device.textColor); XCTAssertTrue(device.tiles)
        XCTAssertEqual(device.icons, ["sun"])
    }

    // Showing the entire source as if rendered would hide the actual server clipping.
    func testClippingWarningComesFromDiagnosticsAndNeverReplacesSource() throws {
        let raw = Data(#"{"diagnostics":{"lines":[{"line":1,"widest":19,"cut":true,"rows_wanted":1,"rows_shown":1}]}}"#.utf8)
        XCTAssertTrue(ComposePreviewNotice(diagnosticsData: raw, stale: false, online: true).clipped)
        XCTAssertFalse(ComposePreviewNotice(diagnosticsData: nil, stale: false, online: true).clipped)
        XCTAssertEqual(ComposePreviewNotice(diagnosticsData: raw, stale: true, online: false).state, .offline)
    }

    private func drawing(source: String) throws -> BoardDrawing {
        try JSONDecoder().decode(BoardDrawing.self, from: Data("""
        {"source":"\(source)","technology":"led_matrix","color":"rgb","font":"3x5","icons":["sun","Bad Icon"],"pixel_width":32,"pixel_height":8,
        "features":{"lowercase":true,"color_text":true,"background":true,"tiles":true,"icons":true,"rgb":true,"solid_shapes":true,"pixels":true}}
        """.utf8))
    }
}
