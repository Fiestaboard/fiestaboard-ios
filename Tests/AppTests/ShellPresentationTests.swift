import XCTest
import SwiftUI
import FiestaBoardAppState
@testable import FiestaBoard

@MainActor final class ShellPresentationTests: XCTestCase {
    func testNativeShellRendersLightDarkAndAX3() {
        for appearance in [ColorScheme.light, .dark] {
            for type in [DynamicTypeSize.large, .accessibility3] {
                let image = IOSSnapshot.image(ShellContainer(selection: .constant(.home), editorOpen: false) { tab in
                    NavigationStack { List { Text(tab.rawValue) }.navigationTitle(tab.rawValue) }
                } accessory: {
                    Text("Now showing · Test page").padding()
                }, appearance: appearance, dynamicType: type)
                XCTAssertEqual(image.size, IOSSnapshot.Device.current.size)
                XCTAssertEqual(image.scale, IOSSnapshot.Device.current.scale)
                let attachment = XCTAttachment(image: image)
                attachment.name = "native-shell-\(appearance)-\(type)-\(IOSSnapshot.Device.current.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
    func testConnectionStatesRenderAtTierOneSizesInLightDarkAndAX3() throws {
        let states: [ShellConnection.Presentation] = [.offline, .unreachable, .connecting(still: false, cached: false), .connecting(still: true, cached: false)]
        for (index, state) in states.enumerated() {
            for appearance in [ColorScheme.light, .dark] {
                for size in [DynamicTypeSize.large, .accessibility3] {
                    let device = IOSSnapshot.Device.current
                    let image = IOSSnapshot.image(NavigationStack {
                        ShellConnectionView(state: state, hub: "Test hub", retry: {}).navigationTitle("Home")
                    }, device: device, appearance: appearance, dynamicType: size)
                    XCTAssertEqual(image.size, device.size)
                    XCTAssertEqual(image.scale, device.scale)
                    XCTAssertNotNil(image.cgImage)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "shell-state-\(index)-\(appearance)-\(size)-\(device.rawValue)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
