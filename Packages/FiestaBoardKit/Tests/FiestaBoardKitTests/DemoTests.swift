import XCTest
@testable import FiestaBoardKit

@MainActor
final class DemoTests: XCTestCase {
    func testDemoIsDeterministicAndActionsAreExplicitlySimulated() async throws {
        let service = try FixtureFiestaBoardService()
        let status = try await service.connect(allowCandidateWrites: false)
        XCTAssertTrue(status.isDemo)
        XCTAssertTrue(service.isDemo)
        let boards = try await service.boards()
        let pages = try await service.pages()
        XCTAssertEqual(boards.first?.id, "board-2")
        XCTAssertEqual(boards.first?.rows, 6)
        XCTAssertEqual(boards.first?.cols, 22)
        XCTAssertEqual(boards.first?.deviceModel, "fiestapanel_split_flap")
        XCTAssertEqual(pages.first?.id, "page-selected")
        let target = try BoardTarget(deployment: service.deployment, boardID: "board-2")
        let initial = try await service.board(target)
        let accepted = try await service.sendText("TESTABCD" + String(repeating: "A", count: 124), to: target)
        let changed = try await service.board(target)
        XCTAssertEqual(accepted.disposition, .accepted)
        XCTAssertEqual(changed.characters?.first.map { Array($0.prefix(8)) }, [20,5,19,20,1,2,3,4])
        XCTAssertNotEqual(initial.characters, changed.characters)
        await service.setSimulation(.held)
        let held = try await service.sendText("WAIT", to: target)
        XCTAssertEqual(held.disposition, .held)
        let heldState = try await service.board(target)
        XCTAssertEqual(heldState.characters, changed.characters)
        let selected = try await service.selectPage(id: "page-selected", on: target)
        XCTAssertEqual(selected.disposition, .selectionStored)
        let selectedState = try await service.board(target)
        XCTAssertEqual(selectedState.activePageID, "page-selected")
        XCTAssertEqual(selectedState.characters, changed.characters)
        await service.setSimulation(.partial)
        do { _ = try await service.sendText("NEXT", to: target); XCTFail("Expected partial") }
        catch { guard case .partialWrite = error as? FiestaBoardError else { return XCTFail("Expected partial") } }
        let partialState = try await service.board(target)
        XCTAssertEqual(partialState.characters?.first.map { Array($0.prefix(4)) }, [14,5,24,20])
        XCTAssertEqual(partialState.characters?.last, changed.characters?.last, "Failed region must retain its earlier content")
        XCTAssertTrue(changed.characters?.last?.contains(1) == true, "Retention assertion needs nonblank previous content")
        for simulation in [FixtureSimulation.rejected, .unknown] {
            await service.setSimulation(simulation)
            do { _ = try await service.sendText("NEXT", to: target); XCTFail("Expected simulation") }
            catch {
                switch simulation {
                case .partial: guard case .partialWrite = error as? FiestaBoardError else { return XCTFail("Expected partial") }
                case .rejected: XCTAssertEqual(error as? FiestaBoardError, .conflict)
                case .unknown: XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome)
                default: XCTFail("Unexpected mode")
                }
            }
        }
    }
}
