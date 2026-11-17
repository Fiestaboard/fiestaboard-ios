import XCTest
import FiestaBoardKit
@testable import FiestaBoardAppState

@MainActor final class HomeUndoStateTests: XCTestCase {
    private func prepared(now: Date) async throws -> (BoardStore, FixtureFiestaBoardService) {
        let service = try FixtureFiestaBoardService(homeAudit: true)
        await service.configureUndo(supported:true,expiresAt:now.addingTimeInterval(30))
        let store = BoardStore(now: { now }); await store.connect(service).value
        await store.refreshHomeUndoCapability().value
        await store.confirm(try XCTUnwrap(store.prepare(.homeCancelOverride))).value
        return (store,service)
    }
    func testExplicitCapabilityAndSingleUseReceiptThroughSharedPreparedAction() async throws {
        let (store,service) = try await prepared(now:Date())
        XCTAssertTrue(store.canUndoHomeOverride)
        let undo = try XCTUnwrap(store.prepare(.homeUndoOverride))
        await store.confirm(undo).value
        XCTAssertFalse(store.canUndoHomeOverride)
        await store.confirm(undo).value
        let restored = await service.restoredBoards
        XCTAssertEqual(restored,["board-2"])
    }
    func testAbsentCapabilityDoesNotRequestOrInventUndo() async throws {
        let service = try FixtureFiestaBoardService(homeAudit:true)
        let store = BoardStore(); await store.connect(service).value
        await store.refreshHomeUndoCapability().value
        await store.confirm(try XCTUnwrap(store.prepare(.homeCancelOverride))).value
        XCTAssertFalse(store.canUndoHomeOverride)
        XCTAssertNil(store.prepare(.homeUndoOverride))
        let optIns = await service.undoOptIns
        XCTAssertEqual(optIns,[false])
    }
    func testExpiryDisplayChangeAndNewerMutationDiscardAuthority() async throws {
        var now = Date()
        let service = try FixtureFiestaBoardService(homeAudit:true)
        await service.configureUndo(supported:true,expiresAt:now.addingTimeInterval(30))
        let store = BoardStore(now:{now}); await store.connect(service).value
        await store.refreshHomeUndoCapability().value
        await store.confirm(try XCTUnwrap(store.prepare(.homeCancelOverride))).value
        XCTAssertTrue(store.canUndoHomeOverride)
        now = now.addingTimeInterval(31)
        XCTAssertFalse(store.canUndoHomeOverride); XCTAssertNil(store.prepare(.homeUndoOverride))
        now = now.addingTimeInterval(-31)
        await store.confirm(try XCTUnwrap(store.prepare(.homePage(id:"page-weather",durationMinutes:nil,untilCanceled:false)))).value
        XCTAssertFalse(store.canUndoHomeOverride)
        await store.confirm(try XCTUnwrap(store.prepare(.homeCancelOverride))).value
        XCTAssertTrue(store.canUndoHomeOverride)
        await store.selectBoard("board-led").value
        await store.selectBoard("board-2").value
        await store.refreshHomeUndoCapability().value
        XCTAssertFalse(store.canUndoHomeOverride)
    }
    func testUnknownUndoConsumesLocalAuthorityAndBlocksAllControlsUntilReadback() async throws {
        let (store,service) = try await prepared(now:Date())
        await service.configureHome(failure:.unknownMutationOutcome)
        await store.confirm(try XCTUnwrap(store.prepare(.homeUndoOverride))).value
        XCTAssertTrue(store.needsReadback)
        XCTAssertFalse(store.canWrite); XCTAssertFalse(store.canUndoHomeOverride)
        XCTAssertNil(store.prepare(.homeCancelOverride))
        await store.refresh().value
        XCTAssertFalse(store.needsReadback); XCTAssertFalse(store.canUndoHomeOverride)
    }
    func testLateOldHubCapabilityCannotGrantNewHubAuthority() async throws {
        let service = try FixtureFiestaBoardService(homeAudit:true)
        await service.configureUndo(supported:true,expiresAt:Date().addingTimeInterval(30))
        let store = BoardStore(); await store.connect(service).value
        await service.configureNextHomeRead(delayed:true)
        let read = store.refreshHomeUndoCapability()
        await service.waitForHomeRead()
        let other = try FixtureFiestaBoardService(homeAudit:true,deploymentString:"https://other.test")
        await store.connect(other).value
        await service.releaseHomeRead(); await read.value
        await store.confirm(try XCTUnwrap(store.prepare(.homeCancelOverride))).value
        let optIns = await other.undoOptIns
        XCTAssertEqual(optIns,[false]); XCTAssertFalse(store.canUndoHomeOverride)
    }
}

extension HomeUndoStateTests {
    func testCanceledCapabilityReadCannotGrantAuthorityAfterPollOwnerStops() async throws {
        let service = try FixtureFiestaBoardService(homeAudit:true)
        await service.configureUndo(supported:true,expiresAt:Date().addingTimeInterval(30))
        let store = BoardStore(); await store.connect(service).value
        await service.configureNextHomeRead(delayed:true)
        let read = store.refreshHomeUndoCapability()
        await service.waitForHomeRead()
        read.cancel()
        await service.releaseHomeRead(); await read.value
        XCTAssertFalse(store.supportsHomeControl(.undoOverride))
    }
    func testReceiptCannotBypassFailedReadbackAndBecomesEligibleOnlyAfterExplicitRefresh() async throws {
        let now = Date(), service = try FixtureFiestaBoardService(homeAudit:true)
        await service.configureUndo(supported:true,expiresAt:now.addingTimeInterval(30))
        let store = BoardStore(now:{now}); await store.connect(service).value
        await store.refreshHomeUndoCapability().value
        await service.configureHome(readbackFailure:.networkUnavailable)
        await store.confirm(try XCTUnwrap(store.prepare(.homeCancelOverride))).value
        XCTAssertTrue(store.needsReadback); XCTAssertFalse(store.canUndoHomeOverride)
        await store.refresh().value
        XCTAssertTrue(store.canUndoHomeOverride)
    }
    func testPendingUndoBlocksEveryBoardControlAndConflictRequiresExplicitReadback() async throws {
        let (store,service) = try await prepared(now:Date())
        await service.configureHome(failure:.rejected(status:409),delayed:true)
        let undo = store.confirm(try XCTUnwrap(store.prepare(.homeUndoOverride)))
        await service.waitForHomeMutation()
        XCTAssertTrue(store.commandBusy); XCTAssertFalse(store.canWrite)
        XCTAssertNil(store.prepare(.homeCancelOverride)); XCTAssertNil(store.prepare(.homeUndoOverride))
        await service.releaseHomeMutation(); await undo.value
        XCTAssertTrue(store.needsReadback); XCTAssertFalse(store.canUndoHomeOverride)
    }
    func testCapabilityAuthLossAndNetworkEpochUseSharedGuards() async throws {
        let service = try FixtureFiestaBoardService(homeAudit:true)
        await service.configureUndo(supported:true,expiresAt:Date().addingTimeInterval(30))
        let store = BoardStore(); await store.connect(service).value
        await service.configureNextHomeRead(delayed:true)
        let old = store.refreshHomeUndoCapability()
        await service.waitForHomeRead()
        store.networkAvailable = false; store.networkAvailable = true
        await service.releaseHomeRead(); await old.value
        await store.probeReachability().value
        await store.confirm(try XCTUnwrap(store.prepare(.homeCancelOverride))).value
        let optIns = await service.undoOptIns
        XCTAssertEqual(optIns,[false])
        await service.configureNextHomeRead(failure:.unauthenticated)
        await store.refreshHomeUndoCapability().value
        XCTAssertNil(store.status); XCTAssertFalse(store.canUndoHomeOverride)
    }
}
