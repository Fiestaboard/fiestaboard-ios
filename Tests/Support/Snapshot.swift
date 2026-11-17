import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import FiestaBoard

/// Static regression renders only. Glass is proven by XCUIScreen in UI tests.
@MainActor enum IOSSnapshot {
    enum Device: String, CaseIterable {
        case phone, pad
        var size: CGSize { self == .phone ? CGSize(width: 402, height: 874) : CGSize(width: 1180, height: 820) }
        var scale: CGFloat { self == .phone ? 3 : 2 }
        static var current: Self { UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone }
    }

    nonisolated static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let frozenDate = Date(timeIntervalSince1970: 1736005260) // 2025-01-04 07:41 America/Los_Angeles
    static var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    enum WindowMode { case detached, activeScene }

    static func image<V: View>(_ view: V, device: Device = .current,
                              size: CGSize? = nil, appearance: ColorScheme = .light,
                              dynamicType: DynamicTypeSize = .large,
                              windowMode: WindowMode = .detached,
                              inspect: ((UIWindow) -> Void)? = nil) -> UIImage {
        let renderSize = size ?? device.size
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let host = UIHostingController(rootView: view
            .environment(\.colorScheme, appearance)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.dynamicTypeSize, dynamicType)
            .environment(\._accessibilityReduceMotion, true)
            .environment(\.parityDate, frozenDate)
            .transaction { $0.disablesAnimations = true })
        host.view.frame = CGRect(origin: .zero, size: renderSize)
        let scene: UIWindowScene?
        if windowMode == .activeScene {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            scene = scenes.first { $0.activationState == .foregroundActive && $0.windows.contains(where: \.isKeyWindow) }
                ?? scenes.first { $0.activationState == .foregroundActive }
            XCTAssertNotNil(scene, "Scene-owned snapshots require the app's active UIWindowScene")
        } else {
            scene = nil
        }
        let previousKeyWindow = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: host.view.frame)
        window.frame = host.view.frame
        window.overrideUserInterfaceStyle = appearance == .dark ? .dark : .light
        window.rootViewController = host
        if scene != nil { window.makeKeyAndVisible() } else { window.isHidden = false }
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        host.view.backgroundColor = appearance == .dark ? .black : .white
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.view.layoutIfNeeded()
        inspect?(window)
        let format = UIGraphicsImageRendererFormat()
        format.scale = device.scale
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: renderSize, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        return image
    }

    /// SnapshotTesting records a missing golden and fails the first comparison.
    static func assertMatches(_ image: UIImage, named name: String, device: Device = .current,
                              file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
        let testClass = URL(fileURLWithPath: "\(file)").deletingPathExtension().lastPathComponent
        let directory = repoRoot.appendingPathComponent("Tests/__Snapshots__/iOS\(osMajor)/\(testClass)").path
        do {
            try FileManager.default.createDirectory(at: ParityOutput.directory, withIntermediateDirectories: true)
            try XCTUnwrap(image.pngData()).write(to: ParityOutput.directory.appendingPathComponent("foundation-\(name)-\(device.rawValue).png"), options: .atomic)
        } catch { XCTFail("Cannot write parity artifact: \(error)", file: file, line: line) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(name)-\(device.rawValue)-iOS\(osMajor)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: attachment.name ?? name) { $0.add(attachment) }
        if let failure = verifySnapshot(of: image,
            as: .image(precision: 1, perceptualPrecision: 0.98, scale: device.scale),
            named: "\(name)-\(device.rawValue)", snapshotDirectory: directory,
            file: file, testName: testName, line: line) {
            XCTFail(failure, file: file, line: line)
        }
    }
}

/// Stable clock injection for fixture views; never changes the system clock.
private struct ParityDateKey: EnvironmentKey {
    static let defaultValue = Date(timeIntervalSince1970: 1736005260)
}
extension EnvironmentValues {
    var parityDate: Date {
        get { self[ParityDateKey.self] }
        set { self[ParityDateKey.self] = newValue }
    }
}

/// Evidence artifacts use the checkout's ignored build directory, as on tvOS.
@MainActor enum ParityOutput {
    static var directory: URL { IOSSnapshot.repoRoot.appendingPathComponent("build/parity") }
    static func writeRuntime() throws {
        let env = ProcessInfo.processInfo.environment
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let device = IOSSnapshot.Device.current
        let value: [String: Any] = [
            "osVersion": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "runtimeBuild": env["SIMULATOR_RUNTIME_BUILD_VERSION"] ?? "unknown",
            "deviceModel": env["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.model,
            "goldenDirectory": "iOS\(IOSSnapshot.osMajor)",
            "scale": UIScreen.main.scale,
            "pointWidth": UIScreen.main.bounds.width, "pointHeight": UIScreen.main.bounds.height,
            "configuredRenderWidth": device.size.width, "configuredRenderHeight": device.size.height,
        ]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("runtime-\(device.rawValue).json"), options: .atomic)
        // Default report identifies the most recent capture; both device records remain artifacts.
        try data.write(to: directory.appendingPathComponent("runtime.json"), options: .atomic)
    }
}
