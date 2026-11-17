import XCTest
import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
@testable import FiestaBoard

@MainActor final class HomeSummaryPresentationTests: XCTestCase {
    func testHomeSummaryLightDarkAndAX3AtTierOneScale() throws {
        let detail = try JSONDecoder().decode(BoardDetail.self, from: Data(#"{"id":"cx-kitchen","name":"Kitchen board","device_type":"flagship","rows":6,"cols":22,"is_primary":true,"paused":false,"schedule_enabled":true,"output":"none","source":"schedule","override_started_at":"2026-11-17T15:00:00Z","override_expires_at":"2026-11-17T17:42:00Z"}"#.utf8))
        let clock = try XCTUnwrap(HomeTiming.instant("2026-11-17T15:00:00Z"))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let inactiveSilence = try JSONDecoder().decode(SilenceStatus.self, from: Data(contentsOf:
            root.appendingPathComponent("Tests/Fixtures/Home/DockerBanners/home-silence.json")))
        let presentation = HomePresentation.make(detail: detail, showing: nil, silence: inactiveSilence, pageNames: [:], now: clock)
        XCTAssertEqual(presentation.overrideRemaining, "2h 42m left")
        XCTAssertEqual(presentation.overrideExpiresAt, clock.addingTimeInterval(9720))
        XCTAssertEqual(presentation.overrideRemainingFraction, 1)
        XCTAssertTrue(presentation.overrideResumesSchedule)
        for appearance in [ColorScheme.light, .dark] {
            for type in [DynamicTypeSize.large, .accessibility3] {
                let device = IOSSnapshot.Device.current
                let image = IOSSnapshot.image(NavigationStack {
                    HomeStatusSummary(presentation: presentation, displayName: "Kitchen board", pageName: "Back soon",
                        canChangePage: true, changePage: {}, canCancel: true, cancel: {}).padding().navigationTitle("Home")
                }, device: device, appearance: appearance, dynamicType: type)
                XCTAssertEqual(image.size, device.size)
                XCTAssertEqual(image.scale, device.scale)
                IOSSnapshot.assertMatches(image, named: "i7-home-summary-\(appearance)-\(type == .large ? "default" : "ax3")", device: device)
            }
        }
    }
}
