import XCTest
import SwiftUI
import UIKit
import FiestaBoardRender
@testable import FiestaBoard

/// Native render contracts; measurement keys are local test identifiers, not Figma node IDs.
@MainActor final class OnboardingPresentationTests: XCTestCase {
    func testNativeActionsRetainTouchTargetsInLightDarkAndAX3() throws {
        let device = IOSSnapshot.Device.current
        for mode in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                FigmaGeometryRegistry.shared.reset()
                let image = IOSSnapshot.image(VStack(spacing: 16) {
                    OnboardingAction(title: "Continue", action: {}).figmaNode("onboarding-test:continue")
                    OnboardingAction(title: "Enter an address instead", primary: false, action: {}).figmaNode("onboarding-test:manual")
                }.padding(16), device: device, appearance: mode, dynamicType: size)
                XCTAssertEqual(image.size, device.size)
                let nodes = FigmaGeometryRegistry.shared.snapshot()
                for key in ["onboarding-test:continue", "onboarding-test:manual"] {
                    let frame = try XCTUnwrap(nodes[key]).frame
                    XCTAssertGreaterThanOrEqual(frame.height, PlatformIOSValues.Touch.minTarget)
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThanOrEqual(frame.minX, 0)
                    XCTAssertLessThanOrEqual(frame.maxX, device.size.width)
                }
            }
        }
    }

    func testOriginalVectorAssetsAreBundledAtTheirUnscaledDimensions() throws {
        let expected: [(String, CGSize)] = [
            ("OnboardingBrand", CGSize(width: 64, height: 64)),
            ("OnboardingBackdropMask", CGSize(width: 720, height: 400)),
            ("OnboardingPrivacy", CGSize(width: 20, height: 20)),
            ("OnboardingHub", CGSize(width: 16, height: 16))
        ]
        for (name, size) in expected {
            let image = try XCTUnwrap(UIImage(named: name), "Required original artwork: \(name)")
            XCTAssertEqual(image.size, size, name)
        }
    }
}
