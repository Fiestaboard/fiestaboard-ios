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

    /// Transparent secondary layers retain outlines (not the display symbol's
    /// default gray screen), while alwaysOriginal preserves that native palette.
    static func symbolImage(_ name: String, color: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            .applying(UIImage.SymbolConfiguration(paletteColors: [color, .clear]))
        return UIImage(systemName: name, withConfiguration: configuration)?.withRenderingMode(.alwaysOriginal)
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
                        if item.image !== normalImages[index] { item.image = normalImages[index] }
                        if item.selectedImage !== selectedImages[index] { item.selectedImage = selectedImages[index] }
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
                    if item.image === normalImages[index] && item.selectedImage === selectedImages[index] { audit.configuredSymbols += 1 }
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
