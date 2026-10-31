// Vendored from fiestaboard-appletv@a3df9c9 Tests/Support/RenderHarness.swift. MIT.
#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoardRender

/// Hosts a SwiftUI view off-screen and forces a layout pass so its `body`
/// actually executes — line coverage on view code without UI automation —
/// and can snapshot it so geometry can be asserted by sampling pixels.
@MainActor
enum RenderHarness {

    nonisolated static let tvSize = CGSize(width: 1024, height: 768)

    static func render<V: View>(_ view: V, size: CGSize = tvSize) {
        let host = UIHostingController(rootView: view.ignoresSafeArea())
        host.view.frame = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Draw `view` into an image so a test can sample what was painted.
    /// Mobile change: `ImageRenderer` instead of `drawHierarchy`, because this
    /// bundle runs without a host app and the snapshotter needs a render server.
    static func image<V: View>(_ view: V, size: CGSize = tvSize) -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage ?? UIImage()
    }
}

extension UIImage {
    /// sRGB components at a point, for geometry assertions.
    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let cg = cgImage, x >= 0, y >= 0, x < cg.width, y < cg.height else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixel, width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: -CGFloat(x), y: -CGFloat(cg.height - y - 1),
                                    width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}
#endif
