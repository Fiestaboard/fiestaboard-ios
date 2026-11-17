import XCTest
import FiestaBoardDocuments
import FiestaBoardKit
@testable import FiestaBoardEditorState

private func page(_ template: String = #"["","","","","",""]"#, extra: String = "") -> Data {
    Data(#"{"id":"p","name":"Doc","type":"template","template":\#(template),"revision":"r1","edit_protocol":"page-revision-v1"\#(extra)}"#.utf8)
}
@MainActor private func makeModel(_ data: Data = page(), remote: EditorRemoteActions? = nil, boards: [EditorBoardChoice] = [], memory: UserDefaults? = nil) throws -> LocalPageEditorModel {
    try LocalPageEditorModel(rawDocumentData: data, identity: DraftIdentity(deploymentID: "https://example.test", pageID: "p"),
                             draftStore: LocalDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
                             remote: remote, boards: boards, boardMemory: memory)
}

/// PLAN B17: typing is held in the text view and committed on 250 ms idle as one session step.
@MainActor final class TypingCommitTests: XCTestCase {
    func testIdleCommitIsOneStep() async throws {
        let model = try makeModel()
        var buffer = ["", "", "", "", "", ""]
        let clock = ManualSleeper()
        let pipeline = PreviewPipeline(sleep: { try await clock.sleep($0) }, commit: { model.commitRows(buffer) }, render: { .local })
        // A burst: type HELLO, press Return mid-word, keep typing on the new row.
        let six = ["", "", "", "", ""]
        for state in [["H"] + six.prefix(5), ["HE"] + six, ["HEL"] + six, ["HEL", "L"] + six, ["HEL", "LO"] + six] {
            buffer = state
            pipeline.edited()
            for _ in 0..<5 { await Task.yield() }
        }
        XCTAssertFalse(model.canUndo, "Nothing reaches the session while typing continues")
        clock.advance()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(model.lines, ["HEL", "LO", "", "", "", "", ""])
        XCTAssertEqual(model.undoActionName, "Typing")
        model.undo()
        XCTAssertEqual(model.lines, ["", "", "", "", "", ""], "One Undo removes the whole burst, Return included")
        XCTAssertFalse(model.canUndo)
        model.redo()
        XCTAssertEqual(model.lines, ["HEL", "LO", "", "", "", "", ""])
    }

    func testCommitOfUnchangedRowsIsNotAStep() throws {
        let model = try makeModel(page(#"["a","B"]"#))
        model.commitRows(["a", "B"])
        XCTAssertFalse(model.canUndo)
        XCTAssertFalse(model.hasServerChanges)
    }

    func testRowInsertSplicesMetadataInTheSameStep() throws {
        let model = try makeModel(page(#"["A","B"]"#, extra: #","line_metadata":[{"alignment":"center","wrap":false},{"alignment":"right","wrap":true}]"#))
        model.commitRows(["A", "", "B"])
        XCTAssertEqual(model.lineAlignment(0), "center")
        XCTAssertEqual(model.lineAlignment(1), "left")
        XCTAssertEqual(model.lineAlignment(2), "right"); XCTAssertTrue(model.lineWrap(2))
        model.undo()
        XCTAssertEqual(model.lines, ["A", "B"]); XCTAssertEqual(model.lineAlignment(1), "right")
    }

    func testStageRendersCommittedDocumentAndHoldsLastFrame() async throws {
        let target = try BoardTarget(deployment: DeploymentURL("https://example.test"), boardID: "kitchen")
        var requests: [String] = []
        let remote = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.invalidResponse },
            preview: { data, _ in
                requests.append(String(decoding: data, as: UTF8.self))
                return try TemplatePreviewResult(rawData: Data(#"{"rendered":"HELLO","lines":["HELLO"],"line_count":1}"#.utf8))
            })
        let model = try makeModel(remote: remote, boards: [EditorBoardChoice(name: "Kitchen", target: target)])
        guard case .local = try await model.renderStage() else { return XCTFail("No display chosen → local projection") }
        model.chooseBoard("kitchen")
        guard case .local = try await model.renderStage() else { return XCTFail("Empty document → no request") }
        XCTAssertTrue(requests.isEmpty)
        model.commitRows(["HELLO", "", "", "", "", ""])
        guard case .server(let result) = try await model.renderStage() else { return XCTFail() }
        XCTAssertEqual(result.lines, ["HELLO"])
        XCTAssertTrue(requests.first?.contains(#""board_id":"kitchen""#) == true, "The chosen display's id is sent with every render")
        model.commitRows(["HELLO!", "", "", "", "", ""])
        XCTAssertNil(model.preview, "`preview` keeps its clear-on-edit contract")
        XCTAssertEqual(model.lastPreview?.lines, ["HELLO"], "The last frame is held")
        XCTAssertTrue(model.previewStale)
    }
}

/// PLAN B25: one status word, derived from server-save state only.
final class SaveStatusChipTests: XCTestCase {
    func testStatusWords() {
        XCTAssertEqual(SaveStatus(remote: .idle, isPreparing: false, hasServerChanges: false).label, "Saved")
        XCTAssertEqual(SaveStatus(remote: .idle, isPreparing: false, hasServerChanges: true).label, "Unsaved changes")
        XCTAssertEqual(SaveStatus(remote: .idle, isPreparing: true, hasServerChanges: true).label, "Saving…")
        XCTAssertEqual(SaveStatus(remote: .saving, isPreparing: false, hasServerChanges: true).label, "Saving…")
        XCTAssertEqual(SaveStatus(remote: .conflict, isPreparing: false, hasServerChanges: true).label, "Conflict")
        XCTAssertEqual(SaveStatus(remote: .comparison, isPreparing: false, hasServerChanges: true).label, "Conflict")
        XCTAssertEqual(SaveStatus(remote: .unknownOutcome, isPreparing: false, hasServerChanges: true).label, "Save result unknown")
        XCTAssertEqual(SaveStatus(remote: .reading, isPreparing: false, hasServerChanges: false).label, "Saved")
    }
    func testOnlyConflictAndUnknownNeedTheBanner() {
        XCTAssertEqual(SaveStatus.allCases.filter(\.needsAttention), [.conflict, .unknown])
    }
    @MainActor func testModelChipFollowsEditsAndSave() async throws {
        let model = try makeModel(page(#"["A"]"#))
        XCTAssertEqual(model.saveStatus, .saved)
        model.commitRows(["B"])
        XCTAssertEqual(model.saveStatus, .unsaved)
        await model.checkpointNow()
        XCTAssertEqual(model.saveStatus, .unsaved, "A local checkpoint is not a server save")
        XCTAssertFalse(model.hasUnsavedChanges, "…but it is a recovery checkpoint")
    }
}

extension EditorTests {
    /// PLAN B20: the stage's display choice survives closing and reopening the editor.
    func testChosenBoardPersists() throws {
        let suite = "editor-board-memory-" + UUID().uuidString
        let memory = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { memory.removePersistentDomain(forName: suite) }
        let deployment = try DeploymentURL("https://example.test")
        let boards = try ["kitchen", "desk"].map { EditorBoardChoice(name: $0.capitalized, target: try BoardTarget(deployment: deployment, boardID: $0)) }
        let first = try makeModel(boards: boards, memory: memory)
        XCTAssertNil(first.rememberedBoardID)
        first.chooseBoard("desk")
        first.endEditingSession()
        let reopened = try makeModel(boards: boards, memory: memory)
        XCTAssertEqual(reopened.rememberedBoardID, "desk")
        let otherDisplays = try makeModel(boards: Array(boards.prefix(1)), memory: memory)
        XCTAssertNil(otherDisplays.rememberedBoardID, "A display that is no longer offered is not restored")
        let unpersisted = try makeModel(boards: boards)
        XCTAssertNil(unpersisted.rememberedBoardID)
    }
}
