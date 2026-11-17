import SwiftUI
import FiestaBoardAppState

/// Native chrome owns glass, tab minimization and adaptive iPad placement.
struct ShellContainer<Destination: View, Accessory: View>: View {
    @Binding var selection: ShellTab
    let editorOpen: Bool
    @ViewBuilder let destination: (ShellTab) -> Destination
    @ViewBuilder let accessory: () -> Accessory
    var body: some View {
        GeometryReader { geometry in
            TabView(selection: $selection) {
                ForEach(ShellTab.allCases) { route in
                    Tab(value: route) { destination(route) } label: {
                        Label(route.rawValue, systemImage: route.symbol)
                    }
                    .accessibilityIdentifier("destination-" + route.rawValue)
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .defaultAdaptableTabBarPlacement(geometry.size.width > geometry.size.height && UIDevice.current.userInterfaceIdiom == .pad && !editorOpen ? .sidebar : .tabBar)
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory { if !editorOpen { accessory() } }
            .toolbar(editorOpen ? .hidden : .automatic, for: .tabBar)
        }
    }
}
