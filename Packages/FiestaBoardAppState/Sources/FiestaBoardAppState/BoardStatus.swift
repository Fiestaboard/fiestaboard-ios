import Foundation
import FiestaBoardKit
import FiestaBoardRender

public extension BoardSummaryFields {
    init(_ summary: BoardSummary) {
        self.init(deviceType: summary.deviceType, rows: summary.rows, cols: summary.cols,
                  deviceModel: summary.deviceModel, charset: summary.charset, output: summary.output)
    }
}

public extension BoardFrame {
    /// The frame `/v1/boards/{id}` reports (`characters`, else `text`, plus `layers`).
    init(_ detail: BoardDetail, expected: Bool = false) {
        let codes = expected ? detail.expectedCharacters : detail.characters
        let layers = (detail.layers ?? []).compactMap { layer -> PixelLayer? in
            guard let data = Data(base64Encoded: layer.rgba) else { return nil }
            return PixelLayer(x: layer.x, y: layer.y, w: layer.width, h: layer.height, rgba: data)
        }
        self.init(rows: detail.summary.rows, cols: detail.summary.cols, codes: codes,
                  message: codes == nil ? detail.text : nil, layers: layers)
    }
}
