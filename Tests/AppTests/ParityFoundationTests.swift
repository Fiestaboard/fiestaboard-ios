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

    func testNativeSeedPalettePreservesSystemBackgroundAndScrollEdgeBehavior() {
        let native = UINavigationBarAppearance()
        native.configureWithTransparentBackground()
        native.backgroundColor = .cyan
        native.shadowColor = .magenta
        native.largeTitleTextAttributes[.foregroundColor] = UIColor.orange
        let styled = NativeSeedChrome.navigationAppearance(native)
        XCTAssertEqual(styled.backgroundColor, native.backgroundColor)
        XCTAssertEqual(styled.backgroundEffect, native.backgroundEffect)
        XCTAssertEqual(styled.shadowColor, native.shadowColor)
        XCTAssertEqual(native.largeTitleTextAttributes[.foregroundColor] as? UIColor, .orange,
                       "The original appearance is not mutated")
    }

    func testNativeSeedPaletteCanStyleATabBarWithoutANavigationController() {
        let root = UIView()
        let tab = UITabBar()
        tab.items = (0..<5).map { UITabBarItem(title: "Item \($0)", image: nil, tag: $0) }
        root.addSubview(tab)
        NativeSeedChrome.apply(in: root)
        let audit = NativeSeedChrome.audit(in: root)
        XCTAssertEqual(audit.styledTabBars, 1)
        XCTAssertEqual(audit.configuredSymbols, 5)
        XCTAssertEqual(audit.navigationBars, 0)
    }

    func testNativeSeedAuditDetectsPartialPaletteAndScrollEdgeDrift() {
        let root = UIView()
        let tab = UITabBar()
        tab.items = (0..<5).map { UITabBarItem(title: "Item \($0)", image: nil, tag: $0) }
        let navigation = UINavigationBar()
        root.addSubview(tab)
        root.addSubview(navigation)
        NativeSeedChrome.apply(in: root)
        XCTAssertTrue(NativeSeedChrome.audit(in: root).paletteApplied)

        let partialTab = NativeSeedChrome.tabAppearance(tab.standardAppearance)
        partialTab.stackedLayoutAppearance.normal.titleTextAttributes[.foregroundColor] = UIColor.purple
        tab.standardAppearance = partialTab
        XCTAssertFalse(NativeSeedChrome.audit(in: root).paletteApplied)
        NativeSeedChrome.apply(in: root)
        XCTAssertTrue(NativeSeedChrome.audit(in: root).paletteApplied)

        let tabEdge = NativeSeedChrome.tabAppearance(tab.standardAppearance)
        tabEdge.inlineLayoutAppearance.normal.iconColor = .purple
        tab.scrollEdgeAppearance = tabEdge
        XCTAssertFalse(NativeSeedChrome.audit(in: root).paletteApplied)
        NativeSeedChrome.apply(in: root)
        XCTAssertTrue(NativeSeedChrome.audit(in: root).paletteApplied)

        let partialNavigation = NativeSeedChrome.navigationAppearance(navigation.standardAppearance)
        partialNavigation.titleTextAttributes[.foregroundColor] = UIColor.purple
        navigation.standardAppearance = partialNavigation
        XCTAssertFalse(NativeSeedChrome.audit(in: root).paletteApplied)
        NativeSeedChrome.apply(in: root)
        XCTAssertTrue(NativeSeedChrome.audit(in: root).paletteApplied)

        let navigationEdge = UINavigationBarAppearance()
        navigationEdge.configureWithTransparentBackground()
        navigationEdge.largeTitleTextAttributes[.foregroundColor] = UIColor.purple
        navigation.scrollEdgeAppearance = navigationEdge
        XCTAssertFalse(NativeSeedChrome.audit(in: root).paletteApplied)
        NativeSeedChrome.apply(in: root)
        XCTAssertTrue(NativeSeedChrome.audit(in: root).paletteApplied)
        XCTAssertNil(navigation.scrollEdgeAppearance?.backgroundEffect)
    }

    func testNativeSymbolCopiesMatchByContentAndRejectWrongPalette() throws {
        let root = UIView()
        let tab = UITabBar()
        tab.items = (0..<5).map { UITabBarItem(title: "Item \($0)", image: nil, tag: $0) }
        root.addSubview(tab)
        NativeSeedChrome.apply(in: root)
        let image = try XCTUnwrap(NativeSeedChrome.symbolImage("display", color: NativeSeedChrome.foreground))
        XCTAssertFalse(image.isSymbolImage, "UIKit must receive frozen native artwork, not a reconfigurable symbol")
        XCTAssertEqual(image.size, CGSize(width: 24, height: 24))
        let copy = UIImage(cgImage: try XCTUnwrap(image.cgImage), scale: image.scale, orientation: .up)
            .withRenderingMode(.alwaysOriginal)
        XCTAssertFalse(copy === image)
        tab.items?[3].image = copy
        XCTAssertEqual(NativeSeedChrome.audit(in: root).configuredSymbols, 5)
        tab.items?[3].image = NativeSeedChrome.symbolImage("display", color: .red)
        XCTAssertEqual(NativeSeedChrome.audit(in: root).configuredSymbols, 4)
        NativeSeedChrome.apply(in: root)
        XCTAssertEqual(NativeSeedChrome.audit(in: root).configuredSymbols, 5)
    }

    func testNativeSymbolRasterKeepsBrandAndForegroundInsteadOfSystemMulticolor() throws {
        for (name, color) in [("house", NativeSeedChrome.brand), ("calendar", NativeSeedChrome.foreground)] {
            let symbol = try XCTUnwrap(NativeSeedChrome.symbolImage(name, color: color))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(size: symbol.size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: symbol.size))
                symbol.draw(at: .zero)
            }
            let pixels = try XCTUnwrap(RGBA(try XCTUnwrap(image.cgImage)))
            var brandPixels = 0
            var invalidPalettePixels = 0
            for y in 0..<pixels.height {
                for x in 0..<pixels.width {
                    let p = try XCTUnwrap(pixels.at(x, y))
                    if p.0 + 2 < p.1 || p.1 + 2 < p.2 || (name == "calendar" && abs(p.0 - p.2) > 6) {
                        invalidPalettePixels += 1
                    }
                    if p.0 - p.1 > 20 && p.1 - p.2 > 20 { brandPixels += 1 }
                }
            }
            XCTAssertEqual(invalidPalettePixels, 0, "Native \(name) must retain the requested palette")
            if name == "house" { XCTAssertGreaterThan(brandPixels, 0) }
        }
    }

    func testNativeDisplaySymbolHasASeeThroughInterior() throws {
        let symbol = try XCTUnwrap(NativeSeedChrome.symbolImage("display", color: .black))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: symbol.size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: symbol.size))
            symbol.draw(at: .zero)
        }
        let pixels = try XCTUnwrap(RGBA(try XCTUnwrap(image.cgImage)))
        let center = try XCTUnwrap(pixels.at(pixels.width / 2, pixels.height / 2))
        XCTAssertGreaterThan(center.0, 240)
        XCTAssertLessThan(center.1, 10)
        XCTAssertLessThan(center.2, 10)
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
        var chrome: NativeSeedChrome.Audit?
        let image = IOSSnapshot.image(ConnectingSeedView(), device: .phone, appearance: .light) { window in
            chrome = NativeSeedChrome.audit(in: window)
        }
        let audit = try XCTUnwrap(chrome)
        XCTAssertGreaterThan(audit.tabBars, 0, "The actual native tab bar must be present")
        XCTAssertGreaterThan(audit.navigationBars, 0, "The actual native navigation bar must be present")
        XCTAssertTrue(audit.paletteApplied, "\(audit)")
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
        try JSONEncoder().encode(audit).write(to: ParityOutput.directory.appendingPathComponent("ios-connecting.chrome.json"))
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
