// Vendored from fiestaboard-tvos@f1fc67d Sources/Render/BoardCanvas.swift. MIT: ThirdPartyNotices/FiestaBoardTV-MIT.txt.
// Mobile changes: FiestaUI face tokens via `FlapPalette` (surface #0d0d0d,
// inset pigment chips, red heart), a parameterised flap step, and the loading
// drum. The debug pacing probe stays in the TV app.
import SwiftUI

/// Paints a `BoardLayout`.
///
/// One `Canvas` rather than a view per flap. Large animated boards reuse
/// prepared moving-face textures; smaller and static boards resolve each
/// distinct glyph once per draw. One shared animation clock pauses when a
/// transition finishes.
public struct BoardCanvas: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transition: BoardFlipTransition?
    @State private var atlas: FlapAtlas?
    @Environment(\.displayScale) private var displayScale

    private let layout: BoardLayout
    private let palette: FlapPalette
    private let animated: Bool
    private let loading: Bool
    private let code62: Code62Glyph
    private let step: TimeInterval

    public init(layout: BoardLayout, palette: FlapPalette = .black, animated: Bool = false,
                loading: Bool = false, code62: Code62Glyph = .degree,
                step: TimeInterval = 0.08) {
        self.layout = layout
        self.palette = palette
        self.animated = animated
        self.loading = loading
        self.code62 = code62
        self.step = step
    }

    /// tvOS-compatible initialiser (tests ported from the TV app use it).
    public init(layout: BoardLayout, background: BoardColor, animated: Bool = false, code62: Code62Glyph = .degree) {
        self.init(layout: layout, palette: .forBoard(background), animated: animated, code62: code62)
    }

    private var atlasKey: FlapAtlas.Key? {
        // The atlas caches faces at the hardware aspect: a stretched board draws tiles directly.
        guard animated, !reduceMotion, !loading, layout.stretch == 1, layout.tiles.count >= 256, layout.tileHeight <= 120 else { return nil }
        return .init(tileHeight: layout.tileHeight, palette: palette, code62: code62, scale: displayScale)
    }

    private var spinning: Bool { loading && !reduceMotion }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: !spinning && (transition == nil || !animated || reduceMotion))) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                Self.paintNoteBezels(layout, palette: palette, in: &context)
                if spinning {
                    Self.paintLoading(layout, palette: palette, code62: code62, step: step, at: timeline.date, in: &context)
                    return
                }
                let active = animated && !reduceMotion ? transition : nil
                if let atlas, atlas.key == atlasKey {
                    atlas.paint(layout, transition: active, at: timeline.date, in: &context)
                } else {
                    Self.paint(layout, palette: palette, transition: active, at: timeline.date, in: &context)
                }
            }
        }
        .frame(width: layout.width, height: layout.height)
        .accessibilityHidden(true)
        .onChange(of: layout.tiles.map(\.cell)) { old, new in
            guard animated, !reduceMotion, old.count == new.count else {
                transition = nil
                return
            }
            let now = Date()
            transition = transition?.retargeted(to: new, at: now)
                ?? BoardFlipTransition(from: old, to: new, code62: code62, startedAt: now, step: step)
        }
        .task(id: atlasKey) {
            guard let key = atlasKey else { atlas = nil; return }
            guard atlas?.key != key else { return }
            atlas = FlapAtlas(tileHeight: key.tileHeight, palette: key.palette,
                              code62: key.code62, scale: key.scale)
        }
        .task(id: transition?.startedAt) {
            guard let startedAt = transition?.startedAt else { return }
            try? await Task.sleep(nanoseconds: UInt64((transition?.duration ?? 0) * 1_000_000_000))
            guard !Task.isCancelled, transition?.startedAt == startedAt else { return }
            transition = nil
        }
    }

    static func paintNoteBezels(_ layout: BoardLayout, palette: FlapPalette,
                                in context: inout GraphicsContext) {
        guard !layout.notes.isEmpty else { return }
        let white = palette.whiteHardware
        let fill = Color(boardHex: (white ? FiestaTokenValues.Board.bezelLight : FiestaTokenValues.Board.bezelDark).hex)
        let edge = Color(boardHex: (white ? FiestaTokenValues.Board.bezelBorderLight
                                     : FiestaTokenValues.Board.bezelBorderDark).hex)
        let border = layout.bezelBorder
        let radius = layout.bezelRadius
        let past = radius + border
        for note in layout.notes {
            var bezel = context
            bezel.clip(to: Path(note.rect))
            var face = note.rect
            if note.openRight { face.size.width += past }
            if note.openBottom { face.size.height += past }
            bezel.fill(Path(roundedRect: face, cornerRadius: radius, style: .circular), with: .color(fill))
            bezel.stroke(Path(roundedRect: face.insetBy(dx: border / 2, dy: border / 2),
                              cornerRadius: max(0, radius - border / 2), style: .circular),
                         with: .color(edge), lineWidth: border)
        }
    }

    static func paintPreparedFace(_ tile: TileRect, code: Int, progress: Double?,
                                  palette: FlapPalette, code62: Code62Glyph,
                                  in context: inout GraphicsContext) {
        let font = BoardFont.glyph(size: tile.height * BoardLayout.fontSizeRatio)
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]
        if let progress {
            let sample = BoardFlipTransition.Sample(previous: tile.cell,
                next: BoardTables.cell(forCode: (code + 1) % 72, code62: code62),
                progress: progress, isAnimating: true, drumCode: code)
            paintSplit(tile: tile, sample: sample, in: &context, resolved: &resolved, font: font, palette: palette)
        } else {
            FlapTilePainter.draw(tile: tile, cell: tile.cell, palette: palette, font: font, in: &context, resolved: &resolved)
        }
        FlapTilePainter.drawSeam(tile: tile, seam: FlapTilePainter.seam(forTileHeight: tile.height), palette: palette, in: &context)
    }

    static func paint(_ layout: BoardLayout, palette: FlapPalette,
                      transition: BoardFlipTransition?, at date: Date,
                      in context: inout GraphicsContext) {
        if transition == nil {
            paintStatic(layout, palette: palette, in: &context)
            return
        }
        paintUnbatched(layout, palette: palette, transition: transition, at: date, in: &context)
    }

    private static func paintUnbatched(_ layout: BoardLayout, palette: FlapPalette,
                                      transition: BoardFlipTransition?, at date: Date,
                                      in context: inout GraphicsContext) {
        let font = BoardFont.glyph(size: layout.fontSize)
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]
        let seam = FlapTilePainter.seam(forTileHeight: layout.tileHeight)
        for (index, tile) in layout.tiles.enumerated() {
            if let sample = transition?.sample(index: index, at: date), sample.isAnimating {
                paintSplit(tile: tile, sample: sample, in: &context, resolved: &resolved, font: font, palette: palette)
            } else {
                FlapTilePainter.draw(tile: tile, cell: tile.cell, palette: palette, font: font, in: &context, resolved: &resolved)
            }
            FlapTilePainter.drawSeam(tile: tile, seam: seam, palette: palette, in: &context)
        }
    }

    /// Canonical row-major grids have disjoint surfaces and a full-point
    /// gutter. Preserve legacy compositing for overlapping/custom/tiny layouts.
    static func canBatchStatic(_ layout: BoardLayout) -> Bool {
        guard layout.notes.isEmpty, layout.tileHeight.isFinite, layout.fontSize.isFinite else { return false }
        var rowY: Double?
        var rowBottom = -Double.infinity
        var lastRight = -Double.infinity
        for tile in layout.tiles {
            guard tile.x.isFinite, tile.y.isFinite, tile.width.isFinite, tile.height.isFinite,
                  tile.width > 0, tile.height >= 5,
                  tile.x == tile.x.rounded(), tile.y == tile.y.rounded(),
                  tile.width == tile.width.rounded(), tile.height == tile.height.rounded() else { return false }
            if tile.y == rowY {
                guard tile.x >= lastRight + 1 else { return false }
            } else {
                guard tile.y >= rowBottom + 1 else { return false }
                rowY = tile.y
            }
            lastRight = tile.x + tile.width
            rowBottom = max(rowBottom, tile.y + tile.height)
        }
        return true
    }

    /// Batch disjoint same-style surfaces and two seam fills instead of
    /// interleaving surface/glyph/seams for every cell. Retain rounded-rect paths.
    /// Content retains its exact painter and resolved-glyph cache. No cell moves,
    /// colour changes, temporal sampling or frame-budget relaxation.
    static func paintStatic(_ layout: BoardLayout, palette: FlapPalette, in context: inout GraphicsContext) {
        guard canBatchStatic(layout) else {
            // Fractional Note geometry can change edge antialiasing when grouped;
            // keep its exact existing composition, as well as custom/tiny layouts.
            paintUnbatched(layout, palette: palette, transition: nil, at: .distantPast, in: &context)
            return
        }
        var surfaces = Path()
        var gaps = Path()
        var highlights = Path()
        let seam = FlapTilePainter.seam(forTileHeight: layout.tileHeight)
        for tile in layout.tiles {
            surfaces.addPath(Path(roundedRect: CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height), cornerRadius: tile.radius))
            let top = (tile.y + tile.height / 2).rounded()
            gaps.addRect(CGRect(x: tile.x, y: top, width: tile.width, height: seam.thickness))
            highlights.addRect(CGRect(x: tile.x, y: top + seam.thickness, width: tile.width, height: seam.thickness))
        }
        context.fill(surfaces, with: .color(Color(rgb: palette.surface)))
        let font = BoardFont.glyph(size: layout.fontSize)
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]
        for tile in layout.tiles {
            FlapTilePainter.drawContent(tile: tile, cell: tile.cell, palette: palette, font: font, in: &context, resolved: &resolved)
        }
        context.fill(gaps, with: .color(Color.black.opacity((palette.whiteHardware ? 0.12 : 0.55) * seam.ink)))
        context.fill(highlights, with: .color(Color.white.opacity((palette.whiteHardware ? 0.55 : 0.10) * seam.ink)))
    }

    static func paintLoading(_ layout: BoardLayout, palette: FlapPalette, code62: Code62Glyph, step: TimeInterval,
                             at date: Date, in context: inout GraphicsContext) {
        let font = BoardFont.glyph(size: layout.fontSize)
        var resolved: [Character: GraphicsContext.ResolvedText] = [:]
        let seam = FlapTilePainter.seam(forTileHeight: layout.tileHeight)
        for (index, tile) in layout.tiles.enumerated() {
            let sample = LoadingDrum.sample(index: index, at: date, step: step, code62: code62)
            paintSplit(tile: tile, sample: sample, in: &context, resolved: &resolved, font: font, palette: palette)
            FlapTilePainter.drawSeam(tile: tile, seam: seam, palette: palette, in: &context)
        }
    }

    /// One drum step of one tile: a leaf hinged on the axle through the
    /// tile's middle falls forward off the top half, passes edge-on, and
    /// lands on the bottom half showing its other face. `FlapPhysics`
    /// decides where the leaf is, how it projects and how it is lit.
    private static func paintSplit(tile: TileRect, sample: BoardFlipTransition.Sample,
                                   in context: inout GraphicsContext,
                                   resolved: inout [Character: GraphicsContext.ResolvedText],
                                   font: Font, palette: FlapPalette) {
        let midX = tile.x + tile.width / 2
        let midY = tile.y + tile.height / 2
        let halfHeight = tile.height / 2
        let top = CGRect(x: tile.x, y: tile.y, width: tile.width, height: halfHeight)
        let bottom = CGRect(x: tile.x, y: midY, width: tile.width, height: halfHeight)

        let angle = FlapPhysics.angle(at: sample.progress)
        let projection = FlapPhysics.projection(angle: angle)
        let shadow = FlapPhysics.castShadow(angle: angle)
        let brightness = FlapPhysics.brightness(angle: angle)
        let showsNext = angle >= .pi / 2

        var newTop = context
        newTop.clip(to: Path(top))
        FlapTilePainter.draw(tile: tile, cell: sample.next, palette: palette, font: font, in: &newTop, resolved: &resolved)

        var oldBottom = context
        oldBottom.clip(to: Path(bottom))
        FlapTilePainter.draw(tile: tile, cell: sample.previous, palette: palette, font: font, in: &oldBottom, resolved: &resolved)
        if shadow.opacity > 0 {
            let face = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
            oldBottom.clip(to: Path(roundedRect: face, cornerRadius: tile.radius))
            let depth = halfHeight * shadow.depth
            oldBottom.fill(Path(CGRect(x: tile.x, y: midY, width: tile.width, height: depth)),
                           with: .color(Color.black.opacity(shadow.opacity * 0.6)))
            oldBottom.fill(Path(CGRect(x: tile.x, y: midY, width: tile.width, height: depth * 0.4)),
                           with: .color(Color.black.opacity(shadow.opacity * 0.5)))
        }

        let leafHeight = halfHeight * projection.height
        guard leafHeight >= 0.5 else { return }
        let outline = leafOutline(tile: tile, midX: midX, midY: midY, height: leafHeight,
                                  widthFactor: projection.widthFactor, hangsBelow: showsNext)

        var leaf = context
        leaf.clip(to: outline)
        leaf.translateBy(x: midX, y: midY)
        leaf.scaleBy(x: projection.widthFactor, y: projection.height)
        leaf.translateBy(x: -midX, y: -midY)
        FlapTilePainter.draw(tile: tile, cell: showsNext ? sample.next : sample.previous, palette: palette,
                             font: font, in: &leaf, resolved: &resolved)

        if brightness < 1 {
            context.fill(outline, with: .color(Color.black.opacity(1 - brightness)))
        }
    }

    private static func leafOutline(tile: TileRect, midX: Double, midY: Double, height: Double,
                                    widthFactor: Double, hangsBelow: Bool) -> Path {
        let direction: Double = hangsBelow ? 1 : -1
        let hingeHalf = tile.width / 2
        let freeHalf = hingeHalf * widthFactor
        let freeY = midY + direction * height
        let rx = min(tile.radius * widthFactor, freeHalf)
        let ry = min(tile.radius * height / (tile.height / 2), height)

        var path = Path()
        path.move(to: CGPoint(x: midX - hingeHalf, y: midY))
        path.addLine(to: CGPoint(x: midX - freeHalf, y: freeY - direction * ry))
        path.addQuadCurve(to: CGPoint(x: midX - freeHalf + rx, y: freeY),
                          control: CGPoint(x: midX - freeHalf, y: freeY))
        path.addLine(to: CGPoint(x: midX + freeHalf - rx, y: freeY))
        path.addQuadCurve(to: CGPoint(x: midX + freeHalf, y: freeY - direction * ry),
                          control: CGPoint(x: midX + freeHalf, y: freeY))
        path.addLine(to: CGPoint(x: midX + hingeHalf, y: midY))
        path.closeSubpath()
        return path
    }
}
