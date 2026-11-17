import CoreGraphics

/// Vertical positioning shared by the real canvas rail gesture and host regression controls.
enum CanvasRevealGeometry {
    static func panelBounds(viewport: CGRect, coveringTop: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        // Scroll limits can leave a native header just inside the actual clip edge.
        (max(viewport.minY, coveringTop), viewport.maxY)
    }

    static func isExposed(_ target: CGRect, top: CGFloat, bottom: CGFloat) -> Bool {
        guard valid(target, top: top, bottom: bottom) else { return false }
        if target.height > bottom - top {
            return target.midY >= top && target.midY <= bottom
        }
        return target.minY >= top && target.maxY <= bottom
    }

    static func scrollDistance(_ target: CGRect, top: CGFloat, bottom: CGFloat) -> CGFloat {
        guard valid(target, top: top, bottom: bottom),
              !isExposed(target, top: top, bottom: bottom) else { return 0 }
        // A fixed step can jump across a narrow full-visibility band forever.
        let remaining = top + (bottom - top) / 2 - target.midY
        let maximumStep = min(160, (bottom - top) / 2)
        return min(maximumStep, max(-maximumStep, remaining))
    }

    private static func valid(_ target: CGRect, top: CGFloat, bottom: CGFloat) -> Bool {
        target.size.height > 0 && target.minY.isFinite && target.maxY.isFinite &&
            top.isFinite && bottom.isFinite && bottom > top && (bottom - top).isFinite
    }
}
