import XCTest
import SwiftUI
import UIKit
import FiestaBoardKit
import FiestaBoardAppState
@testable import FiestaBoard

@MainActor final class ShellPresentationTests: XCTestCase {
    private let appearances: [(String, ColorScheme)] = [("light", .light), ("dark", .dark)]
    private let textSizes: [(String, DynamicTypeSize)] = [("large", .large), ("ax3", .accessibility3)]
    private func hubs() throws -> [SavedServer] {
        [SavedServer(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, deployment: try DeploymentURL("https://kitchen.example"), alias: "Kitchen hub", installationID: "one"),
         SavedServer(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, deployment: try DeploymentURL("https://lobby.example"), alias: "Lobby hub", installationID: "two")]
    }
    private func displays() throws -> [BoardSummary] {
        try JSONDecoder().decode([BoardSummary].self, from: Data(#"[{"id":"kitchen","name":"Kitchen","rows":6,"cols":22,"device_type":"flagship","is_primary":true,"schedule_enabled":false,"paused":false,"output":"vestaboard","charset":"vestaboard_v1"}]"#.utf8))
    }
    /// Mirrors DraftScene's actual generated theme; avoids testing the system's default blue tint.
    private func shellImage<V: View>(_ content: V, device: IOSSnapshot.Device = .current,
                                     size: CGSize? = nil, appearance: ColorScheme = .light,
                                     dynamicType: DynamicTypeSize = .large, inspect: ((UIWindow) -> Void)? = nil) -> UIImage {
        IOSSnapshot.image(content.tint(ShellPalette(appearance: appearance).tint), device: device, size: size,
                          appearance: appearance, dynamicType: dynamicType, inspect: inspect)
    }
    private func shellFixture(route: ShellTab, saved: [SavedServer], boards: [BoardSummary]) -> some View {
        ShellContainer(selection: .constant(route), editorOpen: false) { tab in
            NavigationStack {
                if tab == .more {
                    ShellMoreRoot(hubName: saved[0].alias, host: saved[0].deployment.description,
                                  username: "fixture_admin", savedCount: saved.count, openDisplays: {},
                                  account: { Text("Account") }, hubs: {
                        ShellHubsView(hubs: saved, activeDeployment: saved[0].deployment.description,
                                      busy: false, select: { _ in }, add: {})
                    }, about: { Text("About") })
                } else {
                    ShellConnectionView(state: .connecting(still: false, cached: false), hub: saved[0].alias, retry: {})
                        .navigationTitle(tab.rawValue)
                }
            }
        } accessory: {
            if route == .more {
                ShellDisplayAccessory(displays: boards, selectedID: "kitchen", nowShowing: "Hello World",
                                      hubName: saved[0].alias, host: saved[0].deployment.description,
                                      disabled: false, select: { _ in })
            }
        }
    }

    /// The former unscened/non-key UIWindow cannot establish native bar or visible overlay output.
    func testNativeCaptureOwnsTheKeyWindowAndActualMoreSelection() throws {
        let saved = try hubs(), boards = try displays()
        for (name, appearance, type) in [("light-large", ColorScheme.light, DynamicTypeSize.large),
                                          ("dark-ax3", .dark, .accessibility3)] {
            _ = shellImage(shellFixture(route: .more, saved: saved, boards: boards),
                           appearance: appearance, dynamicType: type, inspect: { window in
                XCTAssertNotNil(window.windowScene, "Native shell captures must attach to an actual scene")
                XCTAssertTrue(window.isKeyWindow, "The captured shell must own native system chrome")
                func findTabs(_ controller: UIViewController) -> UITabBarController? {
                    if let tabs = controller as? UITabBarController { return tabs }
                    return controller.children.lazy.compactMap { findTabs($0) }.first
                }
                if let root = window.rootViewController, let tabs = findTabs(root) {
                    XCTAssertEqual(tabs.selectedIndex, 4, "More stays selected in the actual UIKit owner")
                } else {
                    XCTFail("Native shell has no attached tab controller")
                }
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "i6-original-system-screen-more-" + name
                attachment.lifetime = .keepAlways
                self.add(attachment)
            })
        }
    }

    /// The canonical warm surface comes from generated tokens, not UIKit's grouped gray.
    func testSavedHubsUsesTheGeneratedBackgroundInBothAppearances() throws {
        let saved = try hubs()
        for (appearance, expected) in [(ColorScheme.light, [241, 236, 230]), (.dark, [11, 10, 8])] {
            let image = shellImage(NavigationStack {
                ShellHubsView(hubs: saved, activeDeployment: saved[0].deployment.description, busy: false, select: { _ in }, add: {})
            }, appearance: appearance)
            let cg = try XCTUnwrap(image.cgImage)
            let pixelImage = try XCTUnwrap(cg.cropping(to: CGRect(x: image.scale * 2,
                y: (image.size.height - 100) * image.scale, width: 1, height: 1)))
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let channels = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
            XCTAssertEqual((0..<3).map { Int(channels[$0]) }, expected)
        }
    }

    /// AX3 must enlarge status text as well as the navigation title. This id is a synthetic DEBUG probe.
    func testConnectingLabelScalesAtAccessibilityThree() throws {
        var heights: [CGFloat] = []
        for size in [DynamicTypeSize.large, .accessibility3] {
            FigmaGeometryRegistry.shared.reset()
            _ = shellImage(NavigationStack {
                ShellConnectionView(state: .connecting(still: false, cached: false), hub: "Kitchen hub", retry: {})
                    .navigationTitle("Home")
            }, dynamicType: size)
            let label = try XCTUnwrap(FigmaGeometryRegistry.shared.snapshot()["shell:connecting-label"])
            XCTAssertGreaterThan(label.frame.height, 0)
            heights.append(label.frame.height)
        }
        XCTAssertGreaterThan(heights[1], heights[0] * 1.5, "Connecting text must respect the user's AX3 size")
    }

    func testActualNativeShellMoreAndHubsLightDarkAX3() throws {
        let device = IOSSnapshot.Device.current
        let saved = try hubs(), boards = try displays()
        var layouts = [("default", device.size)]
        if device == .pad { layouts.append(("portrait", CGSize(width: 820, height: 1180))) }
        for (layoutName, bounds) in layouts {
            for (modeName, appearance) in appearances {
                for (typeName, type) in textSizes {
                    for route in [ShellTab.home, .more] {
                        let image = shellImage(shellFixture(route: route, saved: saved, boards: boards),
                                               device: device, size: bounds, appearance: appearance, dynamicType: type)
                        XCTAssertEqual(image.size, bounds)
                        XCTAssertEqual(image.scale, device.scale)
                        IOSSnapshot.assertMatches(image, named: "i6-shell-\(route.rawValue)-\(layoutName)-\(modeName)-\(typeName)", device: device)
                    }
                    let list = shellImage(NavigationStack {
                        ShellHubsView(hubs: saved, activeDeployment: saved[0].deployment.description, busy: false, select: { _ in }, add: {})
                    }, device: device, size: bounds, appearance: appearance, dynamicType: type)
                    IOSSnapshot.assertMatches(list, named: "i6-hubs-\(layoutName)-\(modeName)-\(typeName)", device: device)
                }
            }
        }
    }
    func testOfflineRetainsRenderedCachedBoardAndPagesUnderNeutralBanner() throws {
        let hub = try hubs()[0]
        let detail = try JSONDecoder().decode(BoardDetail.self, from: Data(#"{"id":"kitchen","name":"Kitchen","rows":6,"cols":22,"device_type":"flagship","is_primary":true,"schedule_enabled":false,"paused":false,"output":"vestaboard","charset":"vestaboard_v1","source":"manual","text":"HELLO WORLD","active_page_id":"hello"}"#.utf8))
        let snapshot = ShellSnapshot(hub: hub, capturedAt: IOSSnapshot.frozenDate, board: detail, displayName: "Kitchen", pages: [.init(id: "hello", name: "Hello World")])
        for route in [ShellTab.home, .pages] {
            for (modeName, appearance) in appearances {
                for (typeName, type) in textSizes {
                    FigmaGeometryRegistry.shared.reset()
                    let image = shellImage(NavigationStack {
                        ShellCachedContent(snapshot: snapshot, route: route, offline: true)
                    }, appearance: appearance, dynamicType: type)
                    let nodes = FigmaGeometryRegistry.shared.snapshot()
                    let banner = try XCTUnwrap(nodes["cache:offline"])
                    let screen = CGRect(origin: .zero, size: IOSSnapshot.Device.current.size)
                    XCTAssertGreaterThan(banner.frame.width, 0)
                    XCTAssertGreaterThan(banner.frame.height, 0)
                    XCTAssertEqual(banner.frame.intersection(screen).height, banner.frame.height, accuracy: 0.5,
                                   "The offline banner must be visible, not merely registered offscreen")
                    XCTAssertNil(nodes["cache:updating"], "Offline content must not claim Updating")
                    let content = try XCTUnwrap(nodes[route == .home ? "cache:board" : "cache:page-hello"])
                    XCTAssertGreaterThan(content.frame.width, 0)
                    XCTAssertGreaterThan(content.frame.height, 0)
                    XCTAssertEqual(content.label, route == .home ? "HELLO WORLD" : "Hello World")
                    XCTAssertGreaterThanOrEqual(content.frame.minY, banner.frame.maxY,
                                                "Cached content cannot obscure the offline banner")
                    try FileManager.default.createDirectory(at: ParityOutput.directory, withIntermediateDirectories: true)
                    try FigmaGeometryRegistry.shared.exportData().write(to: ParityOutput.directory.appendingPathComponent(
                        "i6-cache-layout-\(route.rawValue)-\(modeName)-\(typeName)-\(IOSSnapshot.Device.current.rawValue).json"))
                    IOSSnapshot.assertMatches(image, named: "i6-cached-\(route.rawValue)-offline-\(modeName)-\(typeName)")
                }
            }
        }
    }
    func testConnectionStatesLightDarkAndAX3() {
        let states: [(String, ShellConnection.Presentation)] = [("offline", .offline), ("unreachable", .unreachable),
            ("connecting", .connecting(still: false, cached: false)), ("still", .connecting(still: true, cached: false))]
        for (stateName, state) in states {
            for (modeName, appearance) in appearances {
                for (typeName, size) in textSizes {
                    let device = IOSSnapshot.Device.current
                    let image = shellImage(NavigationStack {
                        ShellConnectionView(state: state, hub: "Kitchen hub", retry: {}).navigationTitle("Home")
                    }, device: device, appearance: appearance, dynamicType: size)
                    XCTAssertEqual(image.size, device.size)
                    XCTAssertEqual(image.scale, device.scale)
                    IOSSnapshot.assertMatches(image, named: "i6-state-\(stateName)-\(modeName)-\(typeName)", device: device)
                }
            }
        }
    }
}
