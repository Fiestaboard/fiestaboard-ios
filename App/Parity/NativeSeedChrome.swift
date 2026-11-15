#if DEBUG
import SwiftUI
import UIKit

/// Apply the reference palette through native appearance APIs. No replacement
/// navigation/tab views, images, blur or geometry; system Liquid Glass stays native.
struct NativeSeedChrome: UIViewControllerRepresentable {
    static let foreground = UIColor(red: 15/255, green: 13/255, blue: 10/255, alpha: 1)

    static func tabAppearance() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.selectionIndicatorTintColor = UIColor(red: 252/255, green: 237/255, blue: 213/255, alpha: 1)
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = foreground
            item.normal.titleTextAttributes = [.foregroundColor: foreground]
        }
        return appearance
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) { uiViewController.applyPalette() }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyPalette()
        }

        func applyPalette() {
            guard let tabs = tabBarController, let navigation = navigationController else { return }
            tabs.tabBar.standardAppearance = NativeSeedChrome.tabAppearance()
            tabs.tabBar.scrollEdgeAppearance = NativeSeedChrome.tabAppearance()
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.titleTextAttributes = [.foregroundColor: NativeSeedChrome.foreground]
            appearance.largeTitleTextAttributes = [.foregroundColor: NativeSeedChrome.foreground]
            navigation.navigationBar.standardAppearance = appearance
            navigation.navigationBar.scrollEdgeAppearance = appearance
        }
    }
}
#endif
