import Foundation
import FiestaBoardKit
import FiestaBoardRender

/// The same server-rendered preview conversion serves Pages and Home. No local
/// formula evaluation or placeholder content is substituted for a missing reply.
public enum PagePreviewFrame {
    public static func make(_ preview: PagePreview?, geometry: PageGeometry, model: DisplayModel) -> BoardFrame {
        make(preview, rows: geometry.rows, cols: geometry.cols, model: model)
    }
    public static func make(_ preview: PagePreview?, rows: Int, cols: Int, model: DisplayModel) -> BoardFrame {
        guard let preview, preview.available else { return .empty(rows: rows, cols: cols) }
        let layers = preview.layers.compactMap { layer -> PixelLayer? in
            guard let data = Data(base64Encoded: layer.rgba) else { return nil }
            return PixelLayer(x: layer.x, y: layer.y, w: layer.width, h: layer.height, rgba: data)
        }
        if model.technology == .ledMatrix, let json = preview.cellsJSON,
           let cellRows = (try? JSONSerialization.jsonObject(with: json)) as? [[Any]] {
            return BoardFrame(rows: rows, cols: cols,
                cells: cellRows.map { $0.compactMap(BoardToken.init(json:)) }, layers: layers)
        }
        var frame = BoardFrame.fromLines(preview.lines, rows: rows, cols: cols)
        frame.layers = layers
        return frame
    }
}
