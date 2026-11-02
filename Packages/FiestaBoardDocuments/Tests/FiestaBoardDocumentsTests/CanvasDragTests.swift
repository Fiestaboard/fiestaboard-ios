import Foundation
import XCTest
@testable import FiestaBoardDocuments

/// PLAN B24: direct manipulation on the Shapes tab writes integer lexemes through the retained
/// tree, never a `Double`; a `{{…}}` field locks its axis.
final class CanvasDragTests: XCTestCase {
    private let page = ##"{"id":"p","revision":"r1","type":"template","device_type":"panel","grid_rows":10,"grid_cols":16,"template":["{{date_time.time}}"],"canvases":[{"id":"sun","area":{"row":1,"col":1,"rows":5,"cols":8},"future":{"keep":1.50},"content":{"size":[32,30],"palette":{"a":"yellow"},"pixels":["aa"],"shapes":[{"type":"rect","x":10,"y":4.0,"w":6,"h":3,"fill":"red","extension":900719925474099312345678},{"type":"circle","cx":"{{weather.x}}","cy":8,"r":3,"fill":"blue"},{"type":"gradient","from":"#000033","to":"#3366ff"}]}}]}"##

    private func shape(_ document: PageDocument, _ index: Int) -> CanvasShape {
        CanvasShape(document.legacyCanvases[0].shapes[index])!
    }
    private func lexemes(_ data: Data) -> [String] {
        // Every number token in the serialised document.
        let text = String(decoding: data, as: UTF8.self)
        let regex = try! NSRegularExpression(pattern: #"(?<=[:\[,])-?[0-9][0-9.eE+-]*"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
    }

    func testDragWritesIntegerLexemes() throws {
        var session = try DocumentEditingSession(data: Data(page.utf8))
        let original = session.document
        let origin = shape(original, 0)
        // A finger drag of (+2.4, +6.6) content pixels snaps to (+2, +7).
        let dragged = CanvasShape.moved(origin, dx: 2.4, dy: 6.6)
        XCTAssertEqual(dragged.object["x"], .number("12"))
        XCTAssertEqual(dragged.object["y"], .number("11"), "4.0 + 7 is written as the integer lexeme 11")
        XCTAssertEqual(dragged.object["w"], .number("6"), "untouched fields keep their bytes")
        XCTAssertEqual(dragged.object["extension"], .number("900719925474099312345678"))
        var canvases = original.legacyCanvases
        canvases[0].shapes[0] = dragged.json
        try session.setCanvases(canvases, action: "Move shape")
        XCTAssertEqual(shape(session.document, 0).object["x"], .number("12"))
        for lexeme in lexemes(try session.document.serializedData()) where lexeme.hasPrefix("1") && lexeme.count <= 3 {
            XCTAssertFalse(lexeme == "12.0" || lexeme == "11.0", "never a Double: \(lexeme)")
        }
        // A resize handle snaps too; the rect never inverts.
        let resized = CanvasShape.resized(dragged, handle: .bottomRight, to: 20.7, 13.2)
        XCTAssertEqual(resized.object["w"], .number("9"))
        XCTAssertEqual(resized.object["h"], .number("2"))
        let inverted = CanvasShape.resized(dragged, handle: .bottomRight, to: 0, 0)
        XCTAssertEqual(inverted.object["w"], .number("1"))
        // The whole drag is one undo step and restores the exact original bytes.
        try session.undo()
        XCTAssertEqual(try session.document.serializedData(), try original.serializedData())
        // Inspector entry: an integer stays a number lexeme, partial input stays a string.
        var typed = origin
        typed.setField("x", text: "12")
        XCTAssertEqual(typed.object["x"], .number("12"))
        typed.setField("x", text: "1.")
        XCTAssertEqual(typed.object["x"], .string("1."))
        typed.setField("x", text: "{{a.b}}")
        XCTAssertEqual(typed.object["x"], .string("{{a.b}}"))
    }

    func testExpressionAxisIsLocked() throws {
        let document = try PageDocument(data: Data(page.utf8))
        let circle = shape(document, 1)
        XCTAssertTrue(circle.lockedX)
        XCTAssertFalse(circle.lockedY)
        XCTAssertTrue(circle.hasExpression)
        let moved = CanvasShape.moved(circle, dx: 5, dy: 2)
        XCTAssertEqual(moved.object["cx"], .string("{{weather.x}}"), "the expression is never overwritten")
        XCTAssertEqual(moved.object["cy"], .number("10"))
        XCTAssertNil(circle.bounds(), "no overlay box without a numeric centre; the inspector edits it")
        let resized = CanvasShape.resized(circle, handle: .radius, to: 0, 0)
        XCTAssertEqual(resized.object["cx"], .string("{{weather.x}}"))
        // A rect with an expression width keeps x and w; only the free axis resizes.
        var rect = shape(document, 0)
        rect.setField("w", text: "{{plugin.width}}")
        let r = CanvasShape.resized(rect, handle: .bottomRight, to: 30, 20)
        XCTAssertEqual(r.object["w"], .string("{{plugin.width}}"))
        XCTAssertEqual(r.object["x"], .number("10"))
        XCTAssertEqual(r.object["h"], .number("16"))
        // Gradients, polygons and unknown types are preserved: no drag, no handles.
        let gradient = shape(document, 2)
        XCTAssertTrue(gradient.isPreserved)
        XCTAssertTrue(gradient.handles.isEmpty)
        XCTAssertEqual(CanvasShape.moved(gradient, dx: 3, dy: 3), gradient)
    }

    func testAreaDragAndCanvasSettingsWriteIntegers() throws {
        var document = try PageDocument(data: Data(page.utf8))
        var canvas = document.legacyCanvases[0]
        // Dragging from cell (r2,c3) back to (r0,c1), 0-based, selects rows 1–3, cols 2–4.
        canvas.area = CanvasArea.between((2, 3), (0, 1))
        XCTAssertEqual(canvas.area, CanvasArea(row: 1, col: 2, rows: 3, cols: 3))
        guard case .object(let area) = canvas.object["area"] else { return XCTFail() }
        XCTAssertEqual(area["row"], .number("1"), "unchanged value keeps its lexeme")
        XCTAssertEqual(area["col"], .number("2"))
        canvas.scale = 3
        XCTAssertEqual(canvas.object["scale"], .number("3"))
        canvas.bleed = ["top", "left"]
        XCTAssertEqual(canvas.object["bleed"], .array([.string("top"), .string("left")]))
        canvas.bleed = Set(CanvasLimits.bleedSides)
        XCTAssertEqual(canvas.object["bleed"], .array([.string("all")]))
        canvas.textMode = "flow"
        try document.setCanvases([canvas])
        XCTAssertEqual(document.legacyCanvases[0].object["future"], .object(["keep": .number("1.50")]))
        XCTAssertEqual(CanvasArea(row: 9, col: 15, rows: 4, cols: 4).clamped(rows: 10, cols: 16), CanvasArea(row: 9, col: 15, rows: 2, cols: 2))
        XCTAssertNil(CanvasArea(row: 0, col: 0, rows: 5, cols: 8).clamped(rows: 10, cols: 16))
        XCTAssertEqual(LegacyCanvas.nextID(document.legacyCanvases), "canvas1")
        let added = LegacyCanvas.make(id: "canvas1", area: CanvasArea(row: 1, col: 1, rows: 5, cols: 8))
        XCTAssertEqual(added.object["scale"], .number("1"))
        XCTAssertEqual(added.textMode, "hide")
    }
}
