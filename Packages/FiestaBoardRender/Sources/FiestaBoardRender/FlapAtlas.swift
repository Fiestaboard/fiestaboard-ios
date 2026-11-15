// Vendored from fiestaboard-tvos@f1fc67d Sources/Render/FlapAtlas.swift. MIT: ThirdPartyNotices/FiestaBoardTV-MIT.txt.
import SwiftUI

/// Pre-render the drum's moving faces once per geometry/appearance. Playback
/// stamps textures instead of rebuilding thousands of clipped vector leaves.
/// Twelve phases per 80 ms step bound phase error to 3.4 ms at a 60 Hz display.
final class FlapAtlas: @unchecked Sendable {
    struct Key: Equatable {
        let tileHeight: Double
        let palette: FlapPalette
        let code62: Code62Glyph
        let scale: Double
    }
    static let phases = 12

    /// Keep the expensive SwiftUI image-provider work bounded as well as the
    /// texture dimensions. One phase of twelve faces per render preserves the
    /// 72-code drum while avoiding a lazy 312-face image-provider request.
    struct Packing {
        static let budget = 60 * 1024 * 1024
        let codesPerSheet = 12
        let renderScale: Double
        let padding: Double
        let cellWidth: Int
        let cellHeight: Int
        var sheetWidth: Int { cellWidth * codesPerSheet }
        var sheetHeight: Int { cellHeight }
        var sheetCount: Int { (72 / codesPerSheet) * (FlapAtlas.phases + 1) }
        var byteCount: Int { sheetCount * sheetWidth * sheetHeight * 4 }
        var stride: Double { Double(cellWidth) / renderScale }
        var height: Double { Double(cellHeight) / renderScale }

        init?(tileHeight: Double, scale: Double) {
            guard tileHeight.isFinite, tileHeight > 0, tileHeight <= 120,
                  scale.isFinite else { return nil }
            padding = ceil(tileHeight * BoardGeometry.tileWidthRatio * 0.1) + 1
            let requestedWidth = ceil(tileHeight * BoardGeometry.tileWidthRatio + padding * 2)
            let requestedHeight = ceil(tileHeight) + 4
            let points = requestedWidth * requestedHeight * 72 * Double(FlapAtlas.phases + 1)
            var chosen = min(2, max(1, scale), sqrt(Double(Self.budget) / (points * 4)))
            // Enforce the budget after each axis is rounded to pixels.
            while Int(ceil(requestedWidth * chosen)) * Int(ceil(requestedHeight * chosen)) * 72 * (FlapAtlas.phases + 1) * 4 > Self.budget {
                chosen -= 0.001
            }
            renderScale = chosen
            cellWidth = Int(ceil(requestedWidth * chosen))
            cellHeight = Int(ceil(requestedHeight * chosen))
        }
        func position(code: Int, phase: Int) -> (sheet: Int, x: Int) {
            (phase * (72 / codesPerSheet) + code / codesPerSheet, (code % codesPerSheet) * cellWidth)
        }
    }
    let key: Key
    let packing: Packing
    let verticalPadding = 2.0
    let padding: Double
    let stride: Double
    let height: Double
    let byteCount: Int
    let maximumTextureDimension: Int
    private let images: [CGImage]

    @MainActor
    init?(tileHeight: Double, palette: FlapPalette, code62: Code62Glyph, scale: Double) {
        guard let plan = Packing(tileHeight: tileHeight, scale: scale) else { return nil }
        packing = plan
        key = Key(tileHeight: tileHeight, palette: palette, code62: code62, scale: scale)
        padding = plan.padding
        stride = plan.stride
        height = plan.height
        let pad = plan.padding
        let topPad = verticalPadding
        var faces = Array<CGImage?>(repeating: nil, count: 72 * (Self.phases + 1))
        var bytes = 0
        var maximumDimension = 0
        for phase in 0...Self.phases {
            for group in 0..<(72 / plan.codesPerSheet) {
                let content = Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                    for column in 0..<plan.codesPerSheet {
                        let code = group * plan.codesPerSheet + column
                        let tile = TileRect(row: phase, col: code,
                            x: Double(column) * plan.stride + pad, y: topPad,
                            width: tileHeight * BoardGeometry.tileWidthRatio, height: tileHeight,
                            radius: tileHeight * BoardGeometry.tileRadiusRatio,
                            cell: BoardTables.cell(forCode: code, code62: code62))
                        BoardCanvas.paintPreparedFace(tile, code: code,
                            progress: phase == Self.phases ? nil : Double(phase) / Double(Self.phases),
                            palette: palette, code62: code62, in: &context)
                    }
                }.frame(width: plan.stride * Double(plan.codesPerSheet), height: plan.height)
                let materialized = autoreleasepool { () -> CGImage? in
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = plan.renderScale
                    guard let pending = renderer.cgImage,
                          pending.width == plan.sheetWidth, pending.height == plan.sheetHeight,
                          let bitmap = CGContext(data: nil, width: plan.sheetWidth, height: plan.sheetHeight,
                            bitsPerComponent: 8, bytesPerRow: plan.sheetWidth * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                    // Resolve the small provider immediately into an owned RGBA
                    // bitmap. Crops must not defer a large provider job until a
                    // later animation frame or a test reads the final drum face.
                    bitmap.draw(pending, in: CGRect(x: 0, y: 0, width: plan.sheetWidth, height: plan.sheetHeight))
                    return bitmap.makeImage()
                }
                guard let sheet = materialized else { return nil }
                bytes += sheet.bytesPerRow * sheet.height
                maximumDimension = max(maximumDimension, sheet.width, sheet.height)
                for column in 0..<plan.codesPerSheet {
                    let code = group * plan.codesPerSheet + column
                    let position = plan.position(code: code, phase: phase)
                    guard let face = sheet.cropping(to: CGRect(x: position.x, y: 0,
                        width: plan.cellWidth, height: plan.cellHeight)) else { return nil }
                    faces[phase * 72 + code] = face
                }
            }
        }
        guard faces.allSatisfy({ $0 != nil }), bytes <= 64 * 1024 * 1024 else { return nil }
        byteCount = bytes
        maximumTextureDimension = maximumDimension
        images = faces.compactMap { $0 }
    }

    func image(code: Int, phase: Int?) -> CGImage? {
        let phase = phase ?? Self.phases
        guard (0..<72).contains(code), (0...Self.phases).contains(phase) else { return nil }
        return images[phase * 72 + code]
    }

    func paint(_ layout: BoardLayout, transition: BoardFlipTransition?, at date: Date,
               in context: inout GraphicsContext) {
        var resolved: [Int: GraphicsContext.ResolvedImage] = [:]
        for (index, tile) in layout.tiles.enumerated() {
            let sample = transition?.sample(index: index, at: date)
            let active = sample?.isAnimating == true
            var code = active ? sample!.drumCode! : BoardTables.code(for: tile.cell)
            let phase = active ? min(Self.phases, Int((sample!.progress * Double(Self.phases)).rounded())) : Self.phases
            if active && phase == Self.phases { code = (code + 1) % 72 }
            let id = phase * 72 + code
            let face: GraphicsContext.ResolvedImage
            if let cached = resolved[id] { face = cached }
            else {
                face = context.resolve(Image(decorative: images[id], scale: 1))
                resolved[id] = face
            }
            context.draw(face, in: CGRect(x: tile.x - padding, y: tile.y - verticalPadding, width: stride, height: height))
        }
    }
}
