import XCTest
import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
@testable import FiestaBoard

@MainActor final class HomeSummaryPresentationTests: XCTestCase {
    func testHomeSummaryLightDarkAndAX3AtTierOneScale() throws {
        let detail = try JSONDecoder().decode(BoardDetail.self, from: Data(#"{"id":"kitchen","name":"Kitchen board","device_type":"flagship","rows":6,"cols":22,"is_primary":true,"paused":false,"schedule_enabled":true,"output":"none","source":"schedule","override_started_at":"2026-11-17T15:00:00Z","override_expires_at":"2026-11-17T17:42:00Z"}"#.utf8))
        let clock = try XCTUnwrap(HomeTiming.instant("2026-11-17T15:00:00Z"))
        let presentation = HomePresentation.make(detail: detail, showing: nil, silence: nil, pageNames: [:], now: clock)
        XCTAssertEqual(presentation.overrideRemaining, "2h 42m left")
        for appearance in [ColorScheme.light, .dark] {
            for type in [DynamicTypeSize.large, .accessibility3] {
                let device = IOSSnapshot.Device.current
                let image = IOSSnapshot.image(NavigationStack {
                    HomeStatusSummary(presentation: presentation, displayName: "Kitchen board", pageName: "Back soon",
                        canCancel: true, cancel: {}).padding().navigationTitle("Home")
                }, device: device, appearance: appearance, dynamicType: type)
                XCTAssertEqual(image.size, device.size)
                XCTAssertEqual(image.scale, device.scale)
                IOSSnapshot.assertMatches(image, named: "i7-home-summary-\(appearance)-\(type == .large ? "default" : "ax3")", device: device)
            }
        }
    }
}
