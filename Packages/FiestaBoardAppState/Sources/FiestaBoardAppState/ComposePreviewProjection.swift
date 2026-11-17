import Foundation
import FiestaBoardKit
import FiestaBoardRender

/// The existing shared renderer consumes rich markup and legacy RGBA overlays.
/// It never substitutes source draft text for the actual clipped render result.
public struct ComposePreviewProjection: Sendable {
    public let frame: BoardFrame
    public let model: DisplayModel
    public init(preview: TemplatePreviewResult, summary: BoardSummaryFields, drawing: BoardDrawing?) throws {
        guard case .legacy = preview.surface else { throw FiestaBoardError.previewUnsupported }
        var stored: [String: Any] = [:]
        if let drawing, drawing.isKnownDevice, drawing.technology == "led_matrix" {
            guard let width = drawing.pixelWidth, let height = drawing.pixelHeight,
                  (1...2048).contains(width), (1...2048).contains(height), width * height <= 1_048_576,
                  let font = drawing.font, ["3x5", "5x7"].contains(font) else { throw FiestaBoardError.previewUnsupported }
            let color: [String: Any] = drawing.color == "monochrome"
                ? ["kind": "monochrome", "color": drawing.monochrome ?? "#ffffff"] : ["kind": "rgb"]
            stored["device_model_spec"] = ["technology": "led_matrix", "geometry": ["width": width, "height": height],
                                          "font": font, "color": color] as [String: Any]
        }
        model = DisplayModel(summary: summary, stored: stored)
        var layers: [PixelLayer] = []
        for layer in preview.layers {
            guard layer.x >= 0, layer.y >= 0, (1...2048).contains(layer.width), (1...2048).contains(layer.height),
                  layer.width * layer.height <= 1_048_576, let rgba = Data(base64Encoded: layer.rgba),
                  rgba.count == layer.width * layer.height * 4 else { throw FiestaBoardError.invalidResponse }
            layers.append(.init(x: layer.x, y: layer.y, w: layer.width, h: layer.height, rgba: rgba))
        }
        if let object = try? JSONSerialization.jsonObject(with: preview.rawData) as? [String: Any],
           let rawLayers = object["layers"] as? [Any], rawLayers.count != layers.count { throw FiestaBoardError.invalidResponse }
        frame = BoardFrame(rows: summary.rows, cols: summary.cols, message: preview.rendered, layers: layers)
    }
}
