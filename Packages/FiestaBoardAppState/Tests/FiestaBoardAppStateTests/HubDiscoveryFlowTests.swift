import XCTest
@testable import FiestaBoardAppState

final class HubDiscoveryFlowTests: XCTestCase {
    // Starting the browser from Find hub would present Apple's prompt without our explanation.
    func testFindHubRequiresTheExplanationBeforeBrowsing() {
        var flow = HubDiscoveryFlow()
        XCTAssertFalse(flow.mayBrowse)
        flow.requestDiscovery()
        XCTAssertEqual(flow.phase, .localNetworkExplanation)
        XCTAssertFalse(flow.mayBrowse)
        flow.continueAfterExplanation()
        XCTAssertEqual(flow.phase, .searching)
        XCTAssertTrue(flow.mayBrowse)
    }

    // Taking a manual path must never create a local-network permission request as a side effect.
    func testManualAddressWorksWithoutEverStartingDiscovery() {
        var flow = HubDiscoveryFlow()
        flow.enterAddress()
        XCTAssertEqual(flow.phase, .manualAddress)
        XCTAssertFalse(flow.mayBrowse)
        flow.requestDiscovery()
        XCTAssertEqual(flow.phase, .localNetworkExplanation)
        XCTAssertFalse(flow.mayBrowse)
    }

    // A stale Continue event after cancellation must not restart a browser behind another screen.
    func testStaleContinueCannotStartBrowsingAfterManualEntryOrStop() {
        var flow = HubDiscoveryFlow()
        flow.requestDiscovery()
        flow.enterAddress()
        flow.continueAfterExplanation()
        XCTAssertEqual(flow.phase, .manualAddress)
        XCTAssertFalse(flow.mayBrowse)
        flow.requestDiscovery(); flow.continueAfterExplanation()
        flow.stopSearching()
        XCTAssertEqual(flow.phase, .chooseHub)
        XCTAssertFalse(flow.mayBrowse)
        flow.continueAfterExplanation()
        XCTAssertFalse(flow.mayBrowse)
    }

    // A second explicit search may reuse an already accepted explanation, without auto-searching.
    func testExplicitSearchAfterStoppingDoesNotRepeatTheExplanation() {
        var flow = HubDiscoveryFlow()
        flow.requestDiscovery(); flow.continueAfterExplanation(); flow.stopSearching()
        XCTAssertFalse(flow.mayBrowse)
        flow.requestDiscovery()
        XCTAssertEqual(flow.phase, .searching)
        XCTAssertTrue(flow.mayBrowse)
    }
}
