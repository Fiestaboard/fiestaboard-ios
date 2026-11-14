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

    func testActualTierOneScreenSizeAndScale() throws {
        try ParityOutput.writeRuntime()
        let screen = UIScreen.main
        let size = screen.bounds.size
        let data = try Data(contentsOf: ParityOutput.directory.appendingPathComponent("runtime.json"))
        let runtime = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(runtime["pointWidth"] as? Double), Double(size.width))
        XCTAssertEqual(try XCTUnwrap(runtime["pointHeight"] as? Double), Double(size.height))
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

    func testSnapshotInjectsClockAndReduceMotionIntoView() {
        var observedDate: Date?
        var observedReduceMotion: Bool?
        _ = IOSSnapshot.image(SnapshotEnvironmentProbe { date, reduceMotion in
            observedDate = date
            observedReduceMotion = reduceMotion
        })
        XCTAssertEqual(observedDate, IOSSnapshot.frozenDate)
        XCTAssertEqual(observedReduceMotion, true)
    }

    func testFrozenClockIsSevenFortyOneLosAngeles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let parts = calendar.dateComponents([.hour, .minute], from: IOSSnapshot.frozenDate)
        XCTAssertEqual(parts.hour, 7)
        XCTAssertEqual(parts.minute, 41)
    }

    /// Framework regression fixture, deliberately not a Figma Connecting implementation.
    func testSnapshotFoundationGoldens() {
        for appearance in [ColorScheme.light, .dark] {
            for dynamicType in [DynamicTypeSize.large, .accessibility3] {
                let image = IOSSnapshot.image(Text("7:41").font(.title).padding(24),
                                              appearance: appearance, dynamicType: dynamicType)
                let name = (appearance == .dark ? "dark" : "light") + (dynamicType == .large ? "" : "-AX3")
                IOSSnapshot.assertMatches(image, named: name)
            }
        }
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

private struct SnapshotEnvironmentProbe: View {
    @Environment(\.parityDate) private var date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let report: (Date, Bool) -> Void
    var body: some View {
        Text("Clock probe").onAppear { report(date, reduceMotion) }
    }
}
