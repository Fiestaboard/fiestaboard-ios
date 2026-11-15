import XCTest
import SwiftUI
import UIKit
@testable import FiestaBoard

@MainActor final class ParityFoundationTests: XCTestCase {
    func testScreenshotNormalizationHonorsEveryOrientationAndPreservesPixels() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 6), format: format).image { context in
            for (rect, color) in [
                (CGRect(x: 0, y: 0, width: 2, height: 3), UIColor.red),
                (CGRect(x: 2, y: 0, width: 2, height: 3), UIColor.green),
                (CGRect(x: 0, y: 3, width: 2, height: 3), UIColor.blue),
                (CGRect(x: 2, y: 3, width: 2, height: 3), UIColor.yellow)
            ] { color.setFill(); context.fill(rect) }
        }
        let cases: [(UIImage.Orientation, [Int])] = [
            (.up, [0, 1, 2, 3]), (.upMirrored, [1, 0, 3, 2]),
            (.down, [3, 2, 1, 0]), (.downMirrored, [2, 3, 0, 1]),
            (.left, [1, 3, 0, 2]), (.right, [2, 0, 3, 1]),
            (.leftMirrored, [0, 2, 1, 3]), (.rightMirrored, [3, 1, 2, 0])
        ]
        let source = try XCTUnwrap(portrait.cgImage)
        let sourcePixels = try XCTUnwrap(RGBA(source))
        let colors = [sourcePixels.at(1, 1)!, sourcePixels.at(6, 1)!, sourcePixels.at(1, 10)!, sourcePixels.at(6, 10)!]
        for (orientation, expectedColors) in cases {
            let image = UIImage(cgImage: source, scale: 2, orientation: orientation)
            let normalized = try XCTUnwrap(ScreenCapture.orientedPixels(image))
            let swapsAxes = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
            XCTAssertEqual(normalized.width, swapsAxes ? 12 : 8)
            XCTAssertEqual(normalized.height, swapsAxes ? 8 : 12)
            let pixels = try XCTUnwrap(RGBA(normalized))
            let corners = [(1, 1), (normalized.width - 2, 1), (1, normalized.height - 2), (normalized.width - 2, normalized.height - 2)]
            for (corner, expectedIndex) in zip(corners, expectedColors) {
                let actual = try XCTUnwrap(pixels.at(corner.0, corner.1))
                let expected = colors[expectedIndex]
                XCTAssertEqual(actual.0, expected.0, accuracy: 1, "\(orientation)")
                XCTAssertEqual(actual.1, expected.1, accuracy: 1, "\(orientation)")
                XCTAssertEqual(actual.2, expected.2, accuracy: 1, "\(orientation)")
            }
        }
    }

    func testNativeSeedTabAppearanceUsesTheReferenceSelectedFill() {
        let appearance = NativeSeedChrome.tabAppearance()
        XCTAssertEqual(appearance.selectionIndicatorTintColor, UIColor(red: 252/255, green: 237/255, blue: 213/255, alpha: 1))
        XCTAssertEqual(appearance.stackedLayoutAppearance.normal.iconColor, NativeSeedChrome.foreground)
    }

    func testConnectingLoaderUsesTheBundledOriginalAnimation() throws {
        let animation = try XCTUnwrap(TacoAnimation.shared)
        XCTAssertEqual(animation.images.count, 45)
        XCTAssertEqual(animation.duration, 1.92, accuracy: 0.001)
        XCTAssertEqual(animation.timedImages.count, 48)
    }

    /// I2 seed: real SwiftUI layout, exported independently from the reference metadata.
    func testConnectingSeedCaptureAndSkeletonGeometry() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        FigmaGeometryRegistry.shared.reset()
        let image = IOSSnapshot.image(ConnectingSeedView(), device: .phone, appearance: .light)
        XCTAssertEqual(image.cgImage?.width, 1206)
        XCTAssertEqual(image.cgImage?.height, 2622)
        let nodes = try XCTUnwrap(ParityProbe.nodes(relativeTo: "362:20090"))
        let row = try XCTUnwrap(nodes.first { $0.figma == "seed:connecting" })
        let board = try XCTUnwrap(nodes.first { $0.figma == "seed:board" })
        XCTAssertEqual(board.rect.minX, 16, accuracy: 1)
        XCTAssertEqual(board.rect.width, 370, accuracy: 1)
        XCTAssertEqual(board.rect.height, 150, accuracy: 1)
        XCTAssertEqual(board.rect.minY - row.rect.minY, 36, accuracy: 1)
        for (id, width, height, offset) in [
            ("seed:line-1", 220.0, 18.0, 166.0),
            ("seed:line-2", 300.0, 18.0, 200.0),
            ("seed:action", 160.0, 44.0, 234.0),
            ("seed:row-1", 370.0, 56.0, 294.0),
            ("seed:row-2", 370.0, 56.0, 366.0),
            ("seed:row-3", 370.0, 56.0, 438.0)
        ] {
            let frame = try XCTUnwrap(nodes.first { $0.figma == id }).rect
            XCTAssertEqual(frame.minX, 16, accuracy: 1)
            XCTAssertEqual(frame.width, width, accuracy: 1)
            XCTAssertEqual(frame.height, height, accuracy: 1)
            XCTAssertEqual(frame.minY - board.rect.minY, offset, accuracy: 1)
        }
        try FileManager.default.createDirectory(at: ParityOutput.directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: ParityOutput.directory.appendingPathComponent("ios-connecting.png"))
        let probes = ParityProbe.json(ref: "ios-connecting", root: "362:20090", scale: 3)
        try JSONSerialization.data(withJSONObject: probes, options: [.prettyPrinted, .sortedKeys])
            .write(to: ParityOutput.directory.appendingPathComponent("ios-connecting.probes.json"))
        let attachment = XCTAttachment(image: image)
        attachment.name = "ios-connecting-light"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
