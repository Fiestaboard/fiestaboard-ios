import XCTest
import FiestaBoardDocuments
import FiestaBoardKit
@testable import FiestaBoardEditorState

@MainActor final class EditorTests: XCTestCase {
    private var directory: URL!
    private var store: LocalDraftStore!
    private let identity = DraftIdentity(deploymentID: "https://example.test", pageID: "p")
    private func raw(_ name: String = "Original", revision: String = "r1") -> Data {
        Data("{\"id\":\"p\",\"name\":\"\(name)\",\"type\":\"template\",\"template\":[\"ONE\"],\"revision\":\"\(revision)\",\"edit_protocol\":\"page-revision-v1\"}".utf8)
    }
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = LocalDraftStore(directory: directory)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }
    private func model(_ actions: EditorRemoteActions) throws -> LocalPageEditorModel {
        try LocalPageEditorModel(rawDocumentData: raw(), identity: identity, draftStore: store, remote: actions)
    }
    func testUnsupportedDocumentProtocolsCannotSaveEvenWhenRemoteAllowsWrites() async throws {
        for value in ["\"page-document-v99\"", "{}", "null"] {
            let source = String(decoding: raw(), as: UTF8.self).dropLast() + ",\"document_protocol\":" + value + "}"
            var calls = 0
            let model = try LocalPageEditorModel(rawDocumentData: Data(source.utf8), identity: identity, draftStore: store,
                remote: EditorRemoteActions(disabledReason: { nil }, save: { _ in
                    calls += 1
                    throw FiestaBoardError.invalidResponse
                }))
            model.setName("Edited")
            XCTAssertNotNil(model.serverSaveDisabledReason)
            XCTAssertFalse(model.canSaveToServer)
            await model.saveToServer()
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(model.name, "Original")
        }
    }
    func testSaveSnapshotsBeforeFailureAndKeepsServerDirty() async throws {
        let model = try model(EditorRemoteActions(disabledReason: { nil }, save: { [store, identity] patch in
            guard case .recovered(let draft) = try await store!.load(identity) else { throw FiestaBoardError.invalidResponse }
            XCTAssertEqual(try PageDocument(data: draft.documentData).name, "Edited")
            XCTAssertEqual(patch.expectedRevision, "r1")
            throw FiestaBoardError.unauthenticated
        }))
        model.setName("Edited")
        await model.saveToServer()
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertTrue(model.hasServerChanges)
        XCTAssertEqual(model.name, "Edited")
    }
    func testAcknowledgementClearsUndoAndRequiresLocalCheckpointOfNewRevision() async throws {
        let receipt = raw("Edited", revision: "r2")
        let model = try model(EditorRemoteActions(disabledReason: { nil }, save: { _ in EditorSaveResult(data: receipt) }))
        model.setName("Edited")
        await model.saveToServer()
        XCTAssertFalse(model.hasServerChanges)
        XCTAssertTrue(model.hasUnsavedChanges, "Disk still contains pre-ack revision")
        XCTAssertFalse(model.canUndo)
        model.undo()
        XCTAssertEqual(model.baselineRevision, "r2")
        let localSaved = await model.saveDraft()
        XCTAssertTrue(localSaved)
        XCTAssertFalse(model.hasUnsavedChanges)
    }
    func testRecoveredOldRevisionIsUsedRatherThanFetchedRevision() async throws {
        var old = try DocumentEditingSession(data: raw(revision: "old"))
        try old.setName("Recovered")
        try await store.save(old.snapshot(identity: identity))
        let model = try model(EditorRemoteActions(disabledReason: { nil }, save: { patch in
            XCTAssertEqual(patch.expectedRevision, "old")
            throw FiestaBoardError.pageConflict
        }))
        await model.checkRecovery(); model.recoverDraft()
        await model.saveToServer()
        XCTAssertEqual(model.remoteStatus, .conflict)
        XCTAssertEqual(model.name, "Recovered")
        XCTAssertEqual(model.baselineRevision, "old")
        XCTAssertFalse(model.canSaveToServer)
    }
    func testUnknownOutcomeRequiresReadbackAndExplicitReload() async throws {
        let fresh = raw("Server", revision: "r2")
        let model = try model(EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.unknownMutationOutcome }, fetch: { fresh }))
        model.setName("Edited"); await model.saveToServer()
        XCTAssertEqual(model.remoteStatus, .unknownOutcome)
        XCTAssertFalse(model.canSaveToServer)
        await model.fetchRemoteComparison()
        XCTAssertEqual(model.name, "Edited")
        XCTAssertNotNil(model.remoteComparisonText)
        await model.reloadComparedRemote()
        XCTAssertEqual(model.name, "Server")
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.baselineRevision, "r2")
        guard case .recovered(let preserved) = try await store.load(identity) else { return XCTFail("draft preserved") }
        XCTAssertEqual(try PageDocument(data: preserved.documentData).name, "Edited")
        XCTAssertTrue(model.hasUnsavedChanges)
    }
    func testSaveFreezesEditsWhileAwaitingReceipt() async throws {
        var continuation: CheckedContinuation<EditorSaveResult, any Error>?
        let model = try model(EditorRemoteActions(disabledReason: { nil }, save: { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }))
        model.setName("Edited")
        let task = Task { await model.saveToServer() }
        while continuation == nil { await Task.yield() }
        XCTAssertTrue(model.editingFrozen)
        model.setName("Discarded edit")
        XCTAssertEqual(model.name, "Edited")
        continuation!.resume(returning: EditorSaveResult(data: raw("Edited", revision: "r2")))
        await task.value
        XCTAssertEqual(model.name, "Edited")
        XCTAssertFalse(model.hasServerChanges)
    }
    func testLatePreviewFromOlderEditOrDifferentBoardIsIgnored() async throws {
        let deployment = try DeploymentURL("https://example.test", allowLocalHTTP: false)
        let a = try BoardTarget(deployment: deployment, boardID: "a")
        let b = try BoardTarget(deployment: deployment, boardID: "b")
        var continuation: CheckedContinuation<TemplatePreviewResult, any Error>?
        let actions = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.pageWritesDisabled }, validate: { _, _ in
            try TemplateValidationResult(rawData: Data(#"{"valid":true,"errors":[]}"#.utf8))
        }, preview: { data, target in
            guard case .object(let object) = try LosslessJSON.parse(data) else { throw FiestaBoardError.invalidResponse }
            XCTAssertEqual(object["board_id"], .string(target.boardID))
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        let model = try LocalPageEditorModel(rawDocumentData: raw(), identity: identity, draftStore: store, remote: actions,
            boards: [EditorBoardChoice(name: "A", target: a), EditorBoardChoice(name: "B", target: b)])
        let reply = try TemplatePreviewResult(rawData: Data(#"{"rendered":"ONE","lines":["ONE"],"line_count":1}"#.utf8))
        model.chooseBoard("a")
        let first = Task { await model.evaluate(preview: true) }
        while continuation == nil { await Task.yield() }
        model.setLine(0, text: "NEW")
        continuation!.resume(returning: reply); await first.value
        XCTAssertNil(model.preview)
        continuation = nil
        let second = Task { await model.evaluate(preview: true) }
        while continuation == nil { await Task.yield() }
        model.chooseBoard("b")
        continuation!.resume(returning: reply); await second.value
        XCTAssertNil(model.preview)
    }

    func testRecoveredUnsupportedChangesCannotBeSilentlyDiscardedByPartialSave() async throws {
        let baseline = raw()
        let changed = Data(#"{"id":"p","name":"Edited","type":"template","template":["ONE","NEW SLOT"],"canvases":[{"future":true}],"revision":"r1","edit_protocol":"page-revision-v1"}"#.utf8)
        try await store.save(DraftSnapshot(identity: identity, revision: 1, baselineData: baseline, documentData: changed))
        let model = try model(EditorRemoteActions(disabledReason: { nil }, save: { _ in XCTFail("unsupported edit must stay local"); throw FiestaBoardError.pageWritesDisabled }))
        await model.checkRecovery(); model.recoverDraft()
        XCTAssertFalse(model.canSaveToServer)
        XCTAssertNotNil(model.serverSaveDisabledReason)
    }

    func testLatePreviewAuthenticationLossPreservesLatestEditsDespiteInvalidatedResult() async throws {
        let target = try BoardTarget(deployment: DeploymentURL("https://example.test"), boardID: "a")
        var continuation: CheckedContinuation<TemplatePreviewResult, any Error>?
        let actions = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.pageWritesDisabled },
            validate: { _, _ in throw FiestaBoardError.unauthenticated }, preview: { _, _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            })
        let model = try LocalPageEditorModel(rawDocumentData: raw(), identity: identity, draftStore: store, remote: actions,
            boards: [EditorBoardChoice(name: "A", target: target)])
        model.chooseBoard("a")
        let task = Task { await model.evaluate(preview: true) }
        while continuation == nil { await Task.yield() }
        model.setName("Newer unsaved edit")
        continuation!.resume(throwing: FiestaBoardError.unauthenticated)
        await task.value
        guard case .recovered(let saved) = try await store.load(identity) else { return XCTFail("Authentication loss must preserve current work before coordinator returns") }
        XCTAssertEqual(try PageDocument(data: saved.documentData).name, "Newer unsaved edit")
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertNil(model.preview)
    }

    func testLateAuthenticationLossDoesNotResurrectExplicitlyDiscardedEdits() async throws {
        try await store.save(DocumentEditingSession(data: raw()).snapshot(identity: identity))
        let target = try BoardTarget(deployment: DeploymentURL("https://example.test"), boardID: "a")
        var continuation: CheckedContinuation<TemplatePreviewResult, any Error>?
        let actions = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.pageWritesDisabled },
            validate: { _, _ in throw FiestaBoardError.unauthenticated }, preview: { _, _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            })
        let model = try LocalPageEditorModel(rawDocumentData: raw(), identity: identity, draftStore: store, remote: actions,
            boards: [EditorBoardChoice(name: "A", target: target)])
        model.setName("Deliberately discarded")
        model.chooseBoard("a")
        let task = Task { await model.evaluate(preview: true) }
        while continuation == nil { await Task.yield() }
        model.endEditingSession()
        continuation!.resume(throwing: FiestaBoardError.unauthenticated)
        await task.value
        guard case .recovered(let preserved) = try await store.load(identity) else { return XCTFail("Original draft must remain") }
        XCTAssertEqual(try PageDocument(data: preserved.documentData).name, "Original")
    }

    func testLateStalePreviewMustNotErasePreservedPreReloadDraft() async throws {
        try await assertPreviewAfterReloadPreservesDraft(error: .stalePageContext)
    }

    func testLateSessionLossAfterReloadWithoutNewEditsPreservesPriorDraft() async throws {
        try await assertPreviewAfterReloadPreservesDraft(error: .staleSession)
    }

    func testLateAuthenticationLossAfterReloadWithoutNewEditsPreservesPriorDraft() async throws {
        try await assertPreviewAfterReloadPreservesDraft(error: .unauthenticated)
    }

    func testLateAuthenticationLossAfterReloadAndNewEditsPreservesLatestDeliberateWork() async throws {
        try await assertPreviewAfterReloadPreservesDraft(error: .unauthenticated, editAfterReload: true)
    }

    func testLateAuthenticationLossAfterReloadAndUndoneEditsPreservesPriorDraft() async throws {
        try await assertPreviewAfterReloadPreservesDraft(error: .unauthenticated, editAfterReload: true, undoAfterEdit: true)
    }

    func testDocumentContextInvalidationDoesNotCreateEmergencyCheckpoint() async throws {
        let target = try BoardTarget(deployment: DeploymentURL("https://example.test"), boardID: "a")
        let server = raw("Server", revision: "r2")
        var continuation: CheckedContinuation<TemplatePreviewResult, any Error>?
        let actions = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.pageWritesDisabled },
            fetch: { server }, validate: { _, _ in throw FiestaBoardError.previewUnsupported }, preview: { _, _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            })
        let model = try LocalPageEditorModel(rawDocumentData: raw(), identity: identity, draftStore: store, remote: actions,
            boards: [EditorBoardChoice(name: "A", target: target)])
        model.setName("Local unsaved work")
        model.chooseBoard("a")
        let pending = Task { await model.evaluate(preview: true) }
        while continuation == nil { await Task.yield() }
        await model.fetchRemoteComparison() // Rotates document identity without losing connection.
        continuation!.resume(throwing: FiestaBoardError.stalePageContext)
        await pending.value
        guard case .absent = try await store.load(identity) else { return XCTFail("Context invalidation must not implicitly save") }
        XCTAssertEqual(model.name, "Local unsaved work")
        XCTAssertEqual(model.baselineRevision, "r1")
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    private func assertPreviewAfterReloadPreservesDraft(error: FiestaBoardError, editAfterReload: Bool = false, undoAfterEdit: Bool = false) async throws {
        let target = try BoardTarget(deployment: DeploymentURL("https://example.test"), boardID: "a")
        let server = raw("Server", revision: "r2")
        var continuation: CheckedContinuation<TemplatePreviewResult, any Error>?
        let actions = EditorRemoteActions(disabledReason: { nil }, save: { _ in throw FiestaBoardError.pageWritesDisabled },
            fetch: { server }, validate: { _, _ in throw FiestaBoardError.previewUnsupported }, preview: { _, _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            })
        let model = try LocalPageEditorModel(rawDocumentData: raw(), identity: identity, draftStore: store, remote: actions,
            boards: [EditorBoardChoice(name: "A", target: target)])
        model.setName("Work that must survive reload")
        model.chooseBoard("a")
        let pending = Task { await model.evaluate(preview: true) }
        while continuation == nil { await Task.yield() }
        await model.fetchRemoteComparison()
        await model.reloadComparedRemote()
        guard case .recovered(let before) = try await store.load(identity) else { return XCTFail("Preserved local draft") }
        XCTAssertEqual(try PageDocument(data: before.documentData).name, "Work that must survive reload")
        XCTAssertEqual(model.name, "Server")
        XCTAssertTrue(model.hasUnsavedChanges, "Server adoption is not a saved local checkpoint")
        if editAfterReload { model.setName("New deliberate edit after reload") }
        if undoAfterEdit { model.undo() }
        continuation!.resume(throwing: error)
        await pending.value
        guard case .recovered(let after) = try await store.load(identity) else { return XCTFail("Draft must remain") }
        let expected = editAfterReload && !undoAfterEdit ? "New deliberate edit after reload" : "Work that must survive reload"
        XCTAssertEqual(try PageDocument(data: after.documentData).name, expected)
        XCTAssertEqual(model.baselineRevision, "r2", "No callback may rebase the server baseline")
        XCTAssertTrue(model.hasUnsavedChanges, "Recovery exception must not advance explicit local-save checkpoint")
        XCTAssertNil(model.preview)
    }

}
