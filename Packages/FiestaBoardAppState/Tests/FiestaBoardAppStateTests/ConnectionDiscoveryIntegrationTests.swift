import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class ConnectionDiscoveryIntegrationTests: XCTestCase {
    private func model(_ discovery: RecordingOnboardingDiscovery) -> ConnectionModel {
        ConnectionModel(store: BoardStore(), catalog: ServerCatalog(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), discovery: discovery, preferences: UserDefaults(suiteName: UUID().uuidString)!, serviceFactory: { _ in try! FixtureFiestaBoardService() })
    }

    // Calling the real connection entry point must not touch the browser before contextual consent.
    func testFindHubShowsExplanationWithoutStartingTheBrowser() async {
        let discovery = RecordingOnboardingDiscovery(), model = model(discovery)
        await model.findServers().value
        XCTAssertEqual(model.hubDiscoveryFlow.phase, .localNetworkExplanation)
        XCTAssertFalse(model.searching)
        XCTAssertEqual(discovery.starts, 0)
        await model.continueDiscoveryAfterExplanation().value
        XCTAssertEqual(discovery.starts, 1)
        XCTAssertEqual(model.hubDiscoveryFlow.phase, .chooseHub)
        XCTAssertFalse(model.searching)
        await model.continueDiscoveryAfterExplanation().value
        XCTAssertEqual(discovery.starts, 1, "A stale Continue action cannot browse twice")
    }

    // Manual entry and leaving the explanation remain usable without triggering Apple's permission prompt.
    func testManualPathCancelsTheExplanationAndStaleContinueCannotBrowse() async {
        let discovery = RecordingOnboardingDiscovery(), model = model(discovery)
        await model.findServers().value
        model.enterManualAddress()
        XCTAssertEqual(model.hubDiscoveryFlow.phase, .manualAddress)
        await model.continueDiscoveryAfterExplanation().value
        XCTAssertEqual(discovery.starts, 0)
        XCTAssertEqual(model.hubDiscoveryFlow.phase, .manualAddress)
        XCTAssertFalse(model.searching)
    }

    // Empty discovery is an observed empty result; it must not imply Local Network denial.
    func testExplicitSearchCanReuseExplanationButNeverInventsPermissionDenial() async {
        let discovery = RecordingOnboardingDiscovery(), model = model(discovery)
        await model.findServers().value
        await model.continueDiscoveryAfterExplanation().value
        XCTAssertEqual(discovery.starts, 1)
        XCTAssertTrue(model.discoveredServers.isEmpty)
        XCTAssertEqual(model.hubDiscoveryFlow.phase, .chooseHub)
        XCTAssertNotNil(model.discoveryMessage)
        await model.findServers().value
        XCTAssertEqual(discovery.starts, 2, "Only the second explicit Find action reuses explanation")
        XCTAssertEqual(model.hubDiscoveryFlow.phase, .chooseHub)
    }
}

/// The real browser cannot run on a host unit test; this records its side-effect boundary.
private final class RecordingOnboardingDiscovery: ServerDiscovering, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var starts: Int { lock.withLock { count } }
    func candidates() -> AsyncThrowingStream<DiscoveredServer, Error> { AsyncThrowingStream { $0.finish() } }
    func snapshots() -> AsyncThrowingStream<[DiscoveredServer], Error> {
        lock.withLock { count += 1 }
        return AsyncThrowingStream { $0.yield([]); $0.finish() }
    }
}
