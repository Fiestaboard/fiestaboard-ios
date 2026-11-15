#if DEBUG
import SwiftUI
import UIKit

/// Scoped to this fixture's window. Native bars, layout, backgrounds and glass
/// remain UIKit's; only palette and native SF symbol configurations change.
@MainActor struct NativeSeedChrome: UIViewControllerRepresentable {
    static let foreground = UIColor(red: 15/255, green: 13/255, blue: 10/255, alpha: 1)
    static let selectedFill = UIColor(red: 252/255, green: 237/255, blue: 213/255, alpha: 1)
    static let brand = UIColor(red: 137/255, green: 87/255, blue: 0, alpha: 1)
    private static let symbols = ["house", "square.grid.2x2", "calendar", "display", "ellipsis"]
    private static let normalImages = symbols.compactMap { symbolImage($0, color: foreground) }
    private static let selectedImages = symbols.compactMap { symbolImage($0, color: brand) }

    /// UIKit reconfigures live SF images when assigning them to tab items.
    /// Freeze each configured native glyph once at the measured24pt icon size;
    /// keep the native bars/glass, without reference pixels or custom artwork.
    static func symbolImage(_ name: String, color: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            .applying(UIImage.SymbolConfiguration(paletteColors: [color, .clear]))
            .applying(UIImage.SymbolConfiguration(colorRenderingMode: .flat))
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration),
              symbol.size.width > 0, symbol.size.height > 0 else { return nil }
        let size = CGSize(width: 24, height: 24)
        let ratio = min(size.width / symbol.size.width, size.height / symbol.size.height)
        let bounds = CGRect(x: (size.width - symbol.size.width * ratio) / 2,
                            y: (size.height - symbol.size.height * ratio) / 2,
                            width: symbol.size.width * ratio, height: symbol.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            symbol.draw(in: bounds)
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Compare visible bitmap content, not UIImage identity or PNG metadata.
    /// UITabBarItem is allowed to wrap/copy an image. Normalize both into sRGB.
    private static func imageBytes(_ image: UIImage) -> Data? {
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        return rendered ? Data(bytes) : nil
    }

    private static func imagesMatch(_ actual: UIImage?, _ expected: UIImage) -> Bool {
        guard let actual, !actual.isSymbolImage, actual.size == expected.size, actual.scale == expected.scale,
              actual.imageOrientation == expected.imageOrientation,
              actual.renderingMode == .alwaysOriginal,
              let bytes = imageBytes(actual), let expectedBytes = imageBytes(expected) else { return false }
        return bytes == expectedBytes
    }

    static func tabAppearance(_ native: UITabBarAppearance = UITabBarAppearance()) -> UITabBarAppearance {
        let appearance = UITabBarAppearance(barAppearance: native)
        appearance.selectionIndicatorTintColor = selectedFill
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = foreground
            item.normal.titleTextAttributes[.foregroundColor] = foreground
        }
        return appearance
    }

    static func navigationAppearance(_ native: UINavigationBarAppearance) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance(barAppearance: native)
        appearance.titleTextAttributes[.foregroundColor] = foreground
        appearance.largeTitleTextAttributes[.foregroundColor] = foreground
        return appearance
    }

    struct Audit: Codable, CustomStringConvertible {
        var tabBars = 0
        var navigationBars = 0
        var styledTabBars = 0
        var styledNavigationBars = 0
        var configuredSymbols = 0
        var paletteApplied: Bool {
            tabBars > 0 && navigationBars > 0 && styledTabBars == tabBars && styledNavigationBars == navigationBars
                && configuredSymbols == tabBars * 5
        }
        var description: String { "tabs=\(styledTabBars)/\(tabBars), navigation=\(styledNavigationBars)/\(navigationBars), symbols=\(configuredSymbols)" }
    }

    private static func descendants(in root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap { descendants(in: $0) }
    }

    private static func tabPaletteMatches(_ appearance: UITabBarAppearance) -> Bool {
        appearance.selectionIndicatorTintColor == selectedFill &&
            [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance].allSatisfy {
                $0.normal.iconColor == foreground && $0.normal.titleTextAttributes[.foregroundColor] as? UIColor == foreground
            }
    }

    private static func navigationPaletteMatches(_ appearance: UINavigationBarAppearance) -> Bool {
        appearance.titleTextAttributes[.foregroundColor] as? UIColor == foreground &&
            appearance.largeTitleTextAttributes[.foregroundColor] as? UIColor == foreground
    }

    /// Resolve actual bar views independently. A SwiftUI background controller
    /// need not itself have both navigationController and tabBarController.
    static func apply(in root: UIView) {
        for view in descendants(in: root) {
            if let tab = view as? UITabBar {
                if !tabPaletteMatches(tab.standardAppearance) {
                    tab.standardAppearance = tabAppearance(tab.standardAppearance)
                }
                if let native = tab.scrollEdgeAppearance, !tabPaletteMatches(native) {
                    tab.scrollEdgeAppearance = tabAppearance(native)
                }
                if let items = tab.items, items.count == symbols.count,
                   normalImages.count == items.count, selectedImages.count == items.count {
                    for (index, item) in items.enumerated() {
                        if !imagesMatch(item.image, normalImages[index]) { item.image = normalImages[index] }
                        if !imagesMatch(item.selectedImage, selectedImages[index]) { item.selectedImage = selectedImages[index] }
                    }
                }
            }
            if let bar = view as? UINavigationBar {
                if !navigationPaletteMatches(bar.standardAppearance) {
                    bar.standardAppearance = navigationAppearance(bar.standardAppearance)
                }
                // nil preserves UIKit's derived transparent scroll edge.
                if let native = bar.scrollEdgeAppearance, !navigationPaletteMatches(native) {
                    bar.scrollEdgeAppearance = navigationAppearance(native)
                }
            }
        }
    }

    static func audit(in root: UIView) -> Audit {
        var audit = Audit()
        for view in descendants(in: root) {
            if let tab = view as? UITabBar {
                audit.tabBars += 1
                if tabPaletteMatches(tab.standardAppearance) && (tab.scrollEdgeAppearance.map { tabPaletteMatches($0) } ?? true) {
                    audit.styledTabBars += 1
                }
                for (index, item) in (tab.items ?? []).enumerated() where index < normalImages.count && index < selectedImages.count {
                    if imagesMatch(item.image, normalImages[index]) && imagesMatch(item.selectedImage, selectedImages[index]) { audit.configuredSymbols += 1 }
                }
            }
            if let bar = view as? UINavigationBar {
                audit.navigationBars += 1
                if navigationPaletteMatches(bar.standardAppearance) && (bar.scrollEdgeAppearance.map { navigationPaletteMatches($0) } ?? true) {
                    audit.styledNavigationBars += 1
                }
            }
        }
        return audit
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) { uiViewController.applyPalette() }

    final class Controller: UIViewController {
        private var applying = false
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            DispatchQueue.main.async { [weak self] in self?.applyPalette() }
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); applyPalette() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); applyPalette() }
        func applyPalette() {
            guard !applying, let window = viewIfLoaded?.window else { return }
            applying = true
            defer { applying = false }
            NativeSeedChrome.apply(in: window)
        }
    }
}
#endif
