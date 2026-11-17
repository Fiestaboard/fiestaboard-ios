import XCTest
@testable import FiestaBoardAppState

final class ShellStateTests: XCTestCase {
    func testCanonicalTabOrder() {
        XCTAssertEqual(ShellTab.allCases.map(\.rawValue), ["Home", "Pages", "Schedule", "Displays", "More"])
    }
    func testOfflineTakesPrecedenceOverHubFailure() {
        XCTAssertEqual(ShellConnection.presentation(pathAvailable: false, hubReachable: false, connectingSince: nil, cachedAt: nil, now: 600), .offline)
        XCTAssertEqual(ShellConnection.presentation(pathAvailable: true, hubReachable: false, connectingSince: nil, cachedAt: nil, now: 600), .unreachable)
    }
    func testStillConnectingBeginsAtFiveSecondsAndCacheExpiresAtTenMinutes() {
        XCTAssertEqual(ShellConnection.presentation(pathAvailable: true, hubReachable: false, connectingSince: 596, cachedAt: nil, now: 600), .connecting(still: false, cached: false))
        XCTAssertEqual(ShellConnection.presentation(pathAvailable: true, hubReachable: false, connectingSince: 595, cachedAt: 1, now: 600), .connecting(still: true, cached: true))
        XCTAssertEqual(ShellConnection.presentation(pathAvailable: true, hubReachable: false, connectingSince: 595, cachedAt: 0, now: 600), .connecting(still: true, cached: false))
    }
    func testPathRecoveryDoesNotClaimSuccessfulHubConnection() {
        var state = ShellConnection()
        state.observe(pathAvailable: false, hubReachable: false)
        state.observe(pathAvailable: true, hubReachable: false)
        XCTAssertFalse(state.reconnected)
        state.observe(pathAvailable: true, hubReachable: true)
        XCTAssertTrue(state.reconnected)
        state.dismissReconnected()
        state.observe(pathAvailable: true, hubReachable: true)
        XCTAssertFalse(state.reconnected)
    }
}

extension ShellStateTests {
    func testCacheCannotCrossHubIdentityOrTenMinuteBoundary() {
        var cache = ShellCache<String>()
        cache.store("Maya", for: "https://a.example", at: 10)
        XCTAssertEqual(cache.value(for: "https://a.example", at: 609), "Maya")
        XCTAssertNil(cache.value(for: "https://b.example", at: 609))
        XCTAssertNil(cache.value(for: "https://a.example", at: 610))
        XCTAssertNil(cache.value(for: "https://a.example", at: 9))
        cache.remove(for: "https://a.example")
        XCTAssertNil(cache.value(for: "https://a.example", at: 20))
    }
}
