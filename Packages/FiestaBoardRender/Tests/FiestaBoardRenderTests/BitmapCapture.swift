import SwiftUI

/// Render once into an owned sRGB buffer. Sampling a UIImage's lazy backing
/// can instead wait for a render-server image provider during its first draw.
@MainActor
enum BitmapCapture {
    static func image<V: View>(_ view: V, size: CGSize) -> CGImage? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        var image: CGImage?
        renderer.render(rasterizationScale: 1) { renderedSize, draw in
            guard renderedSize == size,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: Int(size.width.rounded(.up)),
                    height: Int(size.height.rounded(.up)), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            draw(context)
            image = context.makeImage()
        }
        return image
    }
}
