import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class HomeControlStateTests: XCTestCase {
    func testUnknownCancelRequiresExplicitReadBeforeAnotherMutation() async throws {
        let store = BoardStore()
        let service = try FixtureFiestaBoardService(homeAudit: true)
        await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        await service.configureHome(failure: .unknownMutationOutcome)
        await status.clearTemporaryOverride()
        XCTAssertTrue(status.homeControlNeedsReadback)
        XCTAssertFalse(status.canClearOverride)
        await status.clearTemporaryOverride()
        let before = await service.canceledBoards
        XCTAssertEqual(before, ["board-2"], "An ambiguous mutation is never replayed by another tap")
        await status.refreshHomeControlState()
        XCTAssertFalse(status.homeControlNeedsReadback)
        XCTAssertTrue(status.canClearOverride)
    }
    func testCommonHomeBarrierRespectsOfflineAndOtherUnknownWrite() async throws {
        let service = try FixtureFiestaBoardService()
        let store = BoardStore()
        await store.connect(service).value
        XCTAssertTrue(store.canPerformScopedHomeControl)
        store.networkAvailable = false
        XCTAssertFalse(store.canPerformScopedHomeControl)
        store.networkAvailable = true
        await store.probeReachability().value
        XCTAssertTrue(store.canPerformScopedHomeControl)
        await service.setSimulation(.unknown)
        await store.confirm(try XCTUnwrap(store.prepare(.text("UNCONFIRMED")))).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canPerformScopedHomeControl)
    }
}

extension HomeControlStateTests {
    func testUnconfirmedHomeWriteSurvivesSameHubReconnect() async throws {
        let store = BoardStore()
        let service = try FixtureFiestaBoardService(homeAudit: true)
        await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        await service.configureHome(failure: .unknownMutationOutcome)
        await status.clearTemporaryOverride()
        XCTAssertTrue(status.homeControlNeedsReadback)
        await store.connect(try FixtureFiestaBoardService(homeAudit: true)).value
        XCTAssertTrue(status.homeControlNeedsReadback, "Reconnect is not an explicit verification of the mutation result")
        XCTAssertFalse(status.canClearOverride)
    }
}

extension HomeControlStateTests {
    func testPendingHomeCancelBlocksEveryBoardControlAndDuplicateTap() async throws {
        let service = try FixtureFiestaBoardService(homeAudit: true)
        let store = BoardStore(); await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        await service.configureHome(delayed: true)
        let cancel = Task { await status.clearTemporaryOverride() }
        await service.waitForHomeMutation()
        XCTAssertTrue(store.commandBusy)
        XCTAssertFalse(store.canWrite)
        XCTAssertNil(store.prepare(.text("OVERLAP")))
        XCTAssertNil(store.prepare(.restore))
        XCTAssertNil(store.prepare(.configuration(BoardPatch(paused: true))))
        await status.clearTemporaryOverride()
        let calls = await service.canceledBoards
        XCTAssertEqual(calls,["board-2"])
        await service.releaseHomeMutation(); await cancel.value
    }
    func testHomeAcknowledgementWithFailedReadbackBlocksAllBoardControls() async throws {
        let service = try FixtureFiestaBoardService(homeAudit: true)
        let store = BoardStore(); await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        await service.configureHome(readbackFailure: .networkUnavailable)
        await status.clearTemporaryOverride()
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canWrite)
        XCTAssertTrue(status.homeControlNeedsReadback)
        XCTAssertNil(store.prepare(.restore))
    }
    func testWritableLegacyHubDoesNotAuthorizeScopedHomeCancel() async throws {
        let service = try FixtureFiestaBoardService()
        let store = BoardStore(); await store.connect(service).value
        XCTAssertTrue(store.canWrite)
        let status = BoardStatus(store: store, reader: { service })
        XCTAssertFalse(status.canClearOverride)
        await status.clearTemporaryOverride()
        let calls = await service.canceledBoards
        XCTAssertTrue(calls.isEmpty)
    }
}

extension HomeControlStateTests {
    func testOldHomeRefreshCannotClearNewHubsUnknownMutationBarrier() async throws {
        let a = try FixtureFiestaBoardService(homeAudit: true, deploymentString: "https://a.test")
        let b = try FixtureFiestaBoardService(homeAudit: true, deploymentString: "https://b.test")
        let store = BoardStore(); await store.connect(a).value
        var reader: any BoardStatusReading = a
        let status = BoardStatus(store: store, reader: { reader })
        await a.configureNextHomeRead(delayed: true)
        let refresh = Task { await status.refreshHomeControlState() }
        await a.waitForHomeRead()
        reader = b; await store.connect(b).value
        await b.configureHome(failure: .unknownMutationOutcome)
        await status.clearTemporaryOverride()
        XCTAssertTrue(store.needsReadback)
        await a.releaseHomeRead(); await refresh.value
        XCTAssertTrue(store.needsReadback, "A's completion must not issue a verification read on B")
        XCTAssertFalse(store.canWrite)
    }
    func testHomeRefreshAuthenticationLossRetiresConnectedCapability() async throws {
        let service = try FixtureFiestaBoardService(homeAudit: true)
        let store = BoardStore(); await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        await service.configureNextHomeRead(failure: .unauthenticated)
        await status.refreshHomeControlState()
        XCTAssertNil(store.status)
        XCTAssertFalse(store.canWrite)
        XCTAssertFalse(status.canClearOverride)
    }
    func testHomeRefreshNetworkAndRetryAfterUseSharedReachabilityState() async throws {
        for error in [FiestaBoardError.networkUnavailable, .rateLimited(retryAfterSeconds: 90)] {
            let service = try FixtureFiestaBoardService(homeAudit: true)
            let store = BoardStore(); await store.connect(service).value
            let status = BoardStatus(store: store, reader: { service })
            await service.configureNextHomeRead(failure: error)
            await status.refreshHomeControlState()
            if error == .networkUnavailable { XCTAssertEqual(store.hubReachable,false) }
            else { XCTAssertNotNil(store.reachabilityRetryAt); XCTAssertFalse(store.canProbeReachability) }
            XCTAssertFalse(status.canClearOverride)
        }
    }
}

extension HomeControlStateTests {
    func testSupersededSameDisplayRefreshCannotClearOrAnnotateNewUnknownWrite() async throws {
        let service = try FixtureFiestaBoardService(homeAudit: true)
        let store = BoardStore(); await store.connect(service).value
        let status = BoardStatus(store: store, reader: { service })
        await service.configureNextHomeRead(delayed: true)
        let first = Task { await status.refreshHomeControlState() }
        await service.waitForHomeRead()
        await status.refreshHomeControlState()
        await service.configureHome(failure: .unknownMutationOutcome)
        await status.clearTemporaryOverride()
        XCTAssertTrue(store.needsReadback)
        XCTAssertEqual(status.homeControlOutcome,.unconfirmed)
        await service.releaseHomeRead(); await first.value
        XCTAssertTrue(store.needsReadback)
        XCTAssertEqual(status.homeControlOutcome,.unconfirmed, "The older verification cannot replace a newer operation's result")
    }
}
