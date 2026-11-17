import XCTest
import SwiftUI
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
    func testActualNativeShellMoreAndHubsLightDarkAX3() throws {
        let device = IOSSnapshot.Device.current
        let saved = try hubs(), boards = try displays()
        var layouts = [("default", device.size)]
        if device == .pad { layouts.append(("portrait", CGSize(width: 820, height: 1180))) }
        for (layoutName, bounds) in layouts {
            for (modeName, appearance) in appearances {
                for (typeName, type) in textSizes {
                    for route in [ShellTab.home, .more] {
                        let image = IOSSnapshot.image(ShellContainer(selection: .constant(route), editorOpen: false) { tab in
                            NavigationStack {
                                if tab == .more {
                                    ShellMoreRoot(hubName: saved[0].alias, host: saved[0].deployment.description,
                                                  username: "fixture_admin", savedCount: saved.count, openDisplays: {},
                                                  account: { Text("Account") }, hubs: {
                                        ShellHubsView(hubs: saved, activeDeployment: saved[0].deployment.description, busy: false, select: { _ in }, add: {})
                                    }, about: { Text("About") })
                                } else {
                                    ShellConnectionView(state: .connecting(still: false, cached: false), hub: saved[0].alias, retry: {})
                                        .navigationTitle(tab.rawValue)
                                }
                            }
                        } accessory: {
                            if route == .more {
                                ShellDisplayAccessory(displays: boards, selectedID: "kitchen", nowShowing: "Hello World",
                                                      hubName: saved[0].alias, host: saved[0].deployment.description, disabled: false, select: { _ in })
                            }
                        }, device: device, size: bounds, appearance: appearance, dynamicType: type)
                        XCTAssertEqual(image.size, bounds)
                        XCTAssertEqual(image.scale, device.scale)
                        IOSSnapshot.assertMatches(image, named: "i6-shell-\(route.rawValue)-\(layoutName)-\(modeName)-\(typeName)", device: device)
                    }
                    let list = IOSSnapshot.image(NavigationStack {
                        ShellHubsView(hubs: saved, activeDeployment: saved[0].deployment.description, busy: false, select: { _ in }, add: {})
                    }, device: device, size: bounds, appearance: appearance, dynamicType: type)
                    IOSSnapshot.assertMatches(list, named: "i6-hubs-\(layoutName)-\(modeName)-\(typeName)", device: device)
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
                    let image = IOSSnapshot.image(NavigationStack {
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
