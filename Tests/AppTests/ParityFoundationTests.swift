import XCTest
import SwiftUI
import UIKit
@testable import FiestaBoard

@MainActor final class ParityFoundationTests: XCTestCase {
    func testRegistrySortsNodesAndUsesRootRelativeCoordinates() throws {
        let registry = FigmaGeometryRegistry()
        registry.record("root", label: nil, frame: CGRect(x: 10, y: 20, width: 402, height: 874))
        registry.record("child", label: "Connecting", frame: CGRect(x: 30, y: 60, width: 100, height: 30))
        let nodes = try XCTUnwrap(ParityProbe.nodes(relativeTo: "root", in: registry))
        XCTAssertEqual(nodes.map(\.figma), ["child", "root"])
        XCTAssertEqual(nodes.first?.rect, CGRect(x: 20, y: 40, width: 100, height: 30))
        XCTAssertEqual(nodes.first?.label, "Connecting")
        registry.reset()
        XCTAssertNil(ParityProbe.nodes(relativeTo: "root", in: registry))
    }

    func testActualTierOneScreenSizeAndScale() {
        let screen = UIScreen.main
        let size = screen.bounds.size
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(min(size.width, size.height), 820)
            XCTAssertEqual(max(size.width, size.height), 1180)
            XCTAssertEqual(screen.scale, 2)
        } else {
            XCTAssertEqual(size.width, 402)
            XCTAssertEqual(size.height, 874)
            XCTAssertEqual(screen.scale, 3)
        }
    }

    func testFrozenClockIsSevenFortyOneLosAngeles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let parts = calendar.dateComponents([.hour, .minute], from: IOSSnapshot.frozenDate)
        XCTAssertEqual(parts.hour, 7)
        XCTAssertEqual(parts.minute, 41)
    }

    func testLightDarkSnapshotsHaveExactPixelDimensions() throws {
        for device in IOSSnapshot.Device.allCases {
            for appearance in [ColorScheme.light, .dark] {
                let image = IOSSnapshot.image(Text("7:41"), device: device, appearance: appearance)
                XCTAssertEqual(image.cgImage?.width, Int(device.size.width * device.scale))
                XCTAssertEqual(image.cgImage?.height, Int(device.size.height * device.scale))
            }
        }
    }
}
