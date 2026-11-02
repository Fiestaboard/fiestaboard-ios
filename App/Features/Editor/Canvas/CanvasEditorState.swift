import SwiftUI
import UIKit
import FiestaBoardDocuments
import FiestaBoardEditorState
import FiestaBoardRender

/// The canvas editor's words (web `canvasEditor` messages, PLAN B24/B27).
enum CanvasStrings {
    static let text = "Text"
    static let canvases = "Canvases"
    static let editingSurface = "Editing surface"
    static let scrollRail = "Scroll the canvases panel"
    static let title = "Pixel canvases"
    static let description = "Draw any pixel in any colour over an area of the board. Text under a canvas is hidden, or flows around it."
    static let add = "Add canvas"
    static func limitReached(_ max: Int) -> String { "A page holds at most \(max) canvases." }
    static let empty = "No canvases yet."
    static let idLabel = "Canvas ID"
    static let idHint = "Lowercase letters, digits, - and _ (up to 16)."
    static let idInvalid = "Use 1–16 lowercase letters, digits, - or _, not used by another canvas."
    static let delete = "Delete"
    static let areaLabel = "Area (board character cells)"
    static let areaRow = "Row", areaCol = "Column", areaRows = "Rows", areaCols = "Columns"
    static let areaPickerHint = "Drag across the grid to set the area, or use the row and column fields."
    static let bleedLabel = "Bleed to the panel edge"
    static let bleedNames = ["top": "Top", "left": "Left", "right": "Right", "bottom": "Bottom"]
    static let scaleLabel = "Scale"
    static func scaleOption(_ n: Int) -> String { "\(n)× pixels" }
    static let textModeLabel = "Text under the canvas"
    static let textHide = "Hide", textFlow = "Flow around"
    static let tabDraw = "Draw", tabShapes = "Shapes"
    static let brush = "Brush", eraser = "Eraser", clear = "Clear"
    static let colorLabel = "Colour", hexLabel = "Hex colour"
    static let zoomIn = "Zoom in", zoomOut = "Zoom out"
    static func padSize(_ w: Int, _ h: Int) -> String { "\(w) × \(h) pixels" }
    static let padHint = "Drag to paint. Each stroke is one undo step."
    static func tooManyColors(_ max: Int) -> String { "A canvas can use at most \(max) colours." }
    static let drawLayerHint = "Draw edits pixels only. The board shows the canvas background and shapes too."
    static let drawSourceHint = "This canvas uses a source. Drawing edits its fallback pixels; the board shows the source when available."
    static let shapesEmpty = "No shapes yet."
    static let addShape = "Add shape"
    static let shapesHint = "Tap a shape to select it, drag to move it, drag a handle to resize. Values snap to whole pixels."
    static let typeNames = ["rect": "Rectangle", "circle": "Circle", "ellipse": "Ellipse", "line": "Line",
                            "polygon": "Polygon", "text": "Text", "gradient": "Gradient"]
    static func typeName(_ type: String) -> String { typeNames[type] ?? (type.isEmpty ? "Unknown shape" : type) }
    static func shapeTitle(_ index: Int, _ type: String) -> String { "\(index + 1). \(typeName(type))" }
    static let expression = "expression"
    static let preserved = "preserved"
    static let preservedHint = "Shown hatched: the board draws it, and its values are edited below."
    static let fieldNames = ["x": "X", "y": "Y", "w": "Width", "h": "Height", "cx": "Centre X", "cy": "Centre Y", "r": "Radius",
                             "rx": "Radius X", "ry": "Radius Y", "x1": "Start X", "y1": "Start Y", "x2": "End X", "y2": "End Y",
                             "fill": "Fill", "stroke": "Outline", "width": "Line width", "points": "Points", "text": "Text",
                             "color": "Colour", "font": "Font", "from": "From colour", "to": "To colour", "angle": "Angle", "if": "Only if"]
    static func fieldName(_ key: String) -> String { fieldNames[key] ?? key }
    static let fieldHint = "Every field takes a number or colour, or an expression such as {{weather.temperature}}."
    static let moveUp = "Move up", moveDown = "Move down", deleteShape = "Delete shape"
    static let issuesTitle = "Canvas problems"
    static let notPixelNotice = "This page has pixel canvases. This board can't draw them, so their areas stay blank. Preview the page on an LED pixel board to edit them."
    static let readOnly = "These canvases have a shape this editor can't change. Edit them in the web app."
}

/// What the canvas editor holds between edits: the selection, the tools, and the canvases of a
/// gesture in progress (`live`), which the stage draws at once and the session receives only
/// when the gesture ends, as one undo step (PLAN B24, B17).
@MainActor final class CanvasEditorState: ObservableObject {
    enum Tab: String { case draw, shapes }
    enum Tool: String { case brush, eraser }
    static let zooms = [2, 4, 6, 8, 12, 16]

    @Published var selectedID: String?
    @Published var live: [LegacyCanvas]?
    @Published var tab: Tab = .draw
    @Published var selectedShape: Int?
    @Published var tool: Tool = .brush
    @Published var color = CanvasRGBA.parse("red")!
    @Published var zoomIndex = 3
    @Published var drawError: String?

    func canvases(_ model: LocalPageEditorModel) -> [LegacyCanvas] { live ?? model.canvases }
    func selectedIndex(_ canvases: [LegacyCanvas]) -> Int? {
        if let selectedID, let index = canvases.firstIndex(where: { $0.id == selectedID }) { return index }
        return canvases.isEmpty ? nil : 0
    }
}

/// A pixel-matrix display as the editor needs it (PLAN B24: the Text | Canvases toggle appears only
/// for these).
struct PixelDisplay: Equatable {
    var model: DisplayModel
    var board: CanvasBoard

    init?(_ choice: EditorBoardChoice?) {
        guard let choice else { return nil }
        let model = DisplayModel(summary: BoardSummaryFields(deviceType: choice.deviceType, rows: choice.rows ?? 1, cols: choice.cols ?? 1,
                                                             deviceModel: choice.deviceModel, charset: choice.charset), stored: nil)
        guard model.technology == .ledMatrix, case .pixels(let w, let h) = model.geometry else { return nil }
        self.model = model
        board = CanvasBoard(width: w, height: h, glyphWidth: model.font.glyphWidth, glyphHeight: model.font.glyphHeight)
    }

    static let glyphs: CanvasRaster.Glyphs = { font, character in LedRasterizer.glyphRows(character, font: font) }

    /// The canvases as stage layers, drawn by the editor (the server's are used when current).
    func layers(_ canvases: [LegacyCanvas]) -> [PixelLayer] {
        CanvasRaster.layers(canvases, board: board, glyphs: Self.glyphs).map {
            PixelLayer(x: $0.x, y: $0.y, w: $0.width, h: $0.height, rgba: Data($0.rgba))
        }
    }
}

/// Straight RGBA bytes as an image drawn with nearest-neighbour sampling.
enum PixelImage {
    static func make(_ rgba: [UInt8], width: Int, height: Int, checker: Bool = false) -> CGImage? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        var bytes = rgba
        if checker {
            // Transparent pixels show a checker so they read as "nothing here" (web pixel pad).
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                if bytes[i + 3] == 0 { let v: UInt8 = (x + y) % 2 == 0 ? 0x3a : 0x2a; bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v; bytes[i + 3] = 255 }
            } }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

extension CanvasRGBA {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
}

/// Diagonal hatching for "preserved" shapes (gradient, polygon, unknown types).
struct Hatch: Shape {
    var spacing: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY)); path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
