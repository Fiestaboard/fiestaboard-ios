import Foundation
import Combine
import FiestaBoardDocuments
import FiestaBoardKit

@MainActor
public final class LocalPageEditorModel: ObservableObject {
    public let identity: DraftIdentity
    private let draftStore: LocalDraftStore
    @Published private var session: DocumentEditingSession
    @Published public private(set) var message: String?
    @Published public private(set) var isSaving = false
    @Published public private(set) var recoveryNotice: String?
    private var recovery: DraftSnapshot?
    private var corruptDraft = false
    private var recoveryChecked = false

    private let remote: EditorRemoteActions?
    public let boards: [EditorBoardChoice]
    @Published public private(set) var remoteStatus: EditorRemoteStatus = .idle
    @Published public private(set) var selectedBoardID: String?
    @Published public private(set) var validation: TemplateValidationResult?
    @Published public private(set) var preview: TemplatePreviewResult?
    @Published public private(set) var isEvaluating = false
    @Published public private(set) var remoteComparisonText: String?
    private var remoteComparisonData: Data?
    private var evaluationGeneration: UInt64 = 0
    private var isPreparingRemoteSave = false
    private var editingEnded = false
    // A recovery side effect may preserve only content produced since the last intentional
    // checkpoint/adoption. Metadata-only local dirty state after reload is not new local work.
    private var recoveryPreservationBarrier: PageDocument

    public init(rawDocumentData: Data, identity: DraftIdentity, draftStore: LocalDraftStore, remote: EditorRemoteActions? = nil, boards: [EditorBoardChoice] = []) throws {
        self.remote = remote
        self.boards = boards
        self.identity = identity
        self.draftStore = draftStore
        let initialSession = try DocumentEditingSession(data: rawDocumentData)
        session = initialSession
        recoveryPreservationBarrier = initialSession.document
    }
    public var name: String { session.document.name ?? "" }
    public var authoringGeometry: TemplateGeometry? { TemplateGeometry(document: session.document) }
    public var pageType: String { session.document.pageType ?? "Unknown page type" }
    public var lines: [String]? { session.document.editableTemplateLines }
    public var readOnlyDocumentText: String {
        guard let data = try? session.document.serializedData() else { return "Document unavailable" }
        return String(decoding: data, as: UTF8.self)
    }
    public var hasUnsavedChanges: Bool { session.hasUnsavedChanges }
    public var canUndo: Bool { session.canUndo }
    public var canRedo: Bool { session.canRedo }
    public var canRecover: Bool { recovery != nil }
    public var hasCorruptDraft: Bool { corruptDraft }

    public func setName(_ value: String) { mutate { try $0.setName(value) } }
    public func setLine(_ index: Int, text: String) { mutate { try $0.replaceTemplateLine(at: index, with: text) } }
    public func insertLine(after index: Int?) {
        mutate { session in
            if let index {
                guard let lines = session.document.editableTemplateLines, lines.indices.contains(index) else { throw DocumentError.invalidLine }
                try session.insertTemplateLine(at: index + 1, with: "")
            } else { try session.insertTemplateLine(at: 0, with: "") }
        }
    }
    public func removeLine(_ index: Int) { mutate { try $0.removeTemplateLine(at: index) } }
    public func moveLine(_ index: Int, to destination: Int) { mutate { try $0.moveTemplateLine(from: index, to: destination) } }
    public func duplicateLine(_ index: Int) { mutate { try $0.duplicateTemplateLine(at: index) } }
    public func setLineAlignment(_ index: Int, alignment: String) { mutate { try $0.setLineAlignment(at: index, alignment: alignment) } }
    public func setLineWrap(_ index: Int, wrap: Bool) { mutate { try $0.setLineWrap(at: index, wrap: wrap) } }
    public func lineAlignment(_ index: Int) -> String { session.document.lineAlignment(at: index) }
    public func lineWrap(_ index: Int) -> Bool { session.document.lineWrap(at: index) }
    public func undo() { mutate { try $0.undo() } }
    public func redo() { mutate { try $0.redo() } }
    private func mutate(_ operation: (inout DocumentEditingSession) throws -> Void) {
        guard !editingFrozen else { return }
        do {
            let oldRevision = session.revision
            try operation(&session); message = nil
            if session.revision != oldRevision { invalidateEvaluation() }
        }
        catch { message = error.localizedDescription }
    }

    public func checkRecovery() async {
        guard !recoveryChecked else { return }
        recoveryChecked = true
        do {
            switch try await draftStore.load(identity) {
            case .absent: break
            case .recovered(let draft):
                recovery = draft
                let base = try PageDocument(data: draft.baselineData)
                let date = draft.savedAt.formatted(date: .abbreviated, time: .shortened)
                recoveryNotice = base == session.baseline
                    ? "A local draft from \(date) is available. Recover it explicitly or keep the fetched page."
                    : "A local draft from \(date) was based on a different fetched page. Recovery restores that whole draft; it does not merge or send changes."
            case .corrupt:
                corruptDraft = true
                recoveryNotice = "A damaged local draft was found. Its bytes are preserved. Preserve it under a separate filename before saving a new draft."
            }
        } catch {
            message = "Could not check local drafts: \(error.localizedDescription)"
            // Retrying is allowed if the view is presented again or the caller invokes this method.
            recoveryChecked = false
        }
    }

    public func recoverDraft() {
        guard !editingFrozen, let recovery else { return }
        do {
            // Do not replace edits already made while recovery lookup was running.
            guard !session.hasUnsavedChanges else {
                message = "Undo your unsaved changes before recovering this draft."
                return
            }
            try session.recover(recovery)
            recoveryPreservationBarrier = session.document
            invalidateEvaluation()
            self.recovery = nil
            recoveryNotice = nil
            message = "Recovered local draft. No changes were sent to the server."
        } catch { message = error.localizedDescription }
    }

    public func dismissRecovery() {
        recovery = nil
        recoveryNotice = nil
    }

    public func preserveCorruptDraft() async {
        do {
            _ = try await draftStore.quarantineCorruptDraft(identity)
            corruptDraft = false
            recoveryNotice = nil
            message = "Damaged draft preserved separately. You can now save a new local draft."
        } catch { message = error.localizedDescription }
    }

    @discardableResult
    public func saveDraft() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let captured = session.document
            let capturedBaseline = session.baseline
            let snapshot = try session.snapshot(identity: identity)
            try await draftStore.save(snapshot)
            session.markSaved(captured, baseline: capturedBaseline)
            recoveryPreservationBarrier = captured
            recovery = nil
            recoveryNotice = nil
            if session.hasUnsavedChanges {
                message = "Local draft saved. Newer edits are still unsaved. No changes were sent to the server."
                return false
            }
            message = "Local draft saved on this device. No changes were sent to the server."
            return true
        } catch {
            message = "Could not save local draft: \(error.localizedDescription)"
            return false
        }
    }

    public var isSimulated: Bool { remote?.isSimulated ?? false }
    public var editingFrozen: Bool { editingEnded || isPreparingRemoteSave || remoteStatus == .saving || remoteStatus == .reading }
    public var baselineRevision: String? {
        if case .string(let value) = session.baseline.root["revision"] { value } else { nil }
    }
    public var hasServerChanges: Bool {
        session.document.root["name"] != session.baseline.root["name"] ||
        session.document.root["template"] != session.baseline.root["template"] ||
        session.document.root["line_metadata"] != session.baseline.root["line_metadata"]
    }
    public var serverSaveDisabledReason: String? {
        guard let remote else { return "Server saving is unavailable for this local document." }
        if let reason = remote.disabledReason() { return reason }
        let documentProtocol = session.baseline.root["document_protocol"]
        guard session.baseline.root["type"] == .string("template"),
              documentProtocol == nil || documentProtocol == .string("page-document-v1") else {
            return "This document uses an unsupported editing protocol. Keep changes as a local draft."
        }
        guard session.baseline.root["edit_protocol"] == .string("page-revision-v1"),
              let revision = baselineRevision, !revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "This document has no supported page revision protocol. Keep changes as a local draft."
        }
        guard case .object(let changes) = try? session.document.changedFields(from: session.baseline),
              changes.keys.allSatisfy({ ["name", "template", "line_metadata"].contains($0) }) else {
            return "This local document includes changes outside supported name, template, and line metadata fields. Preserve it as a local draft; use the web editor for those changes."
        }
        if session.document.root["line_metadata"] != session.baseline.root["line_metadata"] {
            guard case .array = session.document.root["line_metadata"] else {
                return "Only complete line metadata arrays can be saved. Keep this metadata change as a local draft."
            }
        }
        guard let lines = session.document.editableTemplateLines,
              session.baseline.editableTemplateLines != nil else {
            return "This template or its metadata cannot be safely saved. Keep it as a local draft."
        }
        guard !lines.isEmpty else { return "Add at least one template line before saving to the server." }
        if remoteStatus == .conflict { return "The page changed on the server. Fetch it for comparison before choosing a reload." }
        if remoteStatus == .unknownOutcome { return "The save result is unknown. Fetch the server page and choose a reload before another save." }
        if remoteStatus == .comparison { return "Choose whether to reload the compared page. Local work stays preserved in the draft." }
        return nil
    }
    public var canSaveToServer: Bool {
        !editingFrozen && !isSaving && hasServerChanges && serverSaveDisabledReason == nil && remoteStatus == .idle
    }
    public var canFetchRemote: Bool { remote?.fetch != nil && !editingFrozen && !isSaving }
    public var canEvaluate: Bool { remote?.validate != nil && remote?.preview != nil && selectedTarget != nil && !editingFrozen }
    private var selectedTarget: BoardTarget? { boards.first { $0.id == selectedBoardID }?.target }

    /// Call on an explicit Close/Discard decision. Late authentication callbacks must not turn
    /// deliberately discarded work into a new recovery draft.
    public func endEditingSession() {
        editingEnded = true
        invalidateEvaluation()
    }

    public func chooseBoard(_ id: String?) {
        guard id != selectedBoardID else { return }
        selectedBoardID = id
        invalidateEvaluation()
    }
    private func invalidateEvaluation() {
        evaluationGeneration &+= 1
        validation = nil; preview = nil; isEvaluating = false
    }

    /// Called only after the UI's explicit confirmation identifying the page and deployment.
    /// Freeze edits before the local checkpoint so a 401/logout cannot discard the captured work.
    public func saveToServer() async {
        guard canSaveToServer, let remote, let revision = baselineRevision else { return }
        let name = session.document.root["name"] != session.baseline.root["name"] ? session.document.name : nil
        let template = session.document.root["template"] != session.baseline.root["template"] ? session.document.editableTemplateLines : nil
        let metadata = session.document.root["line_metadata"] != session.baseline.root["line_metadata"]
            ? (try? session.document.root["line_metadata"]?.serializedData()) : nil
        let patch = PageSavePatch(name: name, template: template, lineMetadataData: metadata, expectedRevision: revision)
        isPreparingRemoteSave = true
        guard await saveDraft() else { isPreparingRemoteSave = false; return }
        isPreparingRemoteSave = false
        remoteStatus = .saving
        invalidateEvaluation()
        do {
            let receipt = try await remote.save(patch)
            let data = receipt.data
            let accepted = try PageDocument(data: data)
            guard accepted.root["revision"] != nil, accepted.root["edit_protocol"] == .string("page-revision-v1") else {
                throw FiestaBoardError.unknownMutationOutcome
            }
            try session.adoptServerDocument(data)
            recoveryPreservationBarrier = session.document
            remoteStatus = .idle
            message = (isSimulated ? "Simulated save. " : "") + "Page storage acknowledged. Running displays may use this persisted page. Save the updated revision locally to refresh your recovery checkpoint."
            if receipt.incompatibleReferenceCount > 0 {
                message = (message ?? "") + " \(receipt.incompatibleReferenceCount) page references may be incompatible; review them in the web interface."
            }
        } catch FiestaBoardError.pageConflict {
            remoteStatus = .conflict
            message = "The server page changed. Your edited draft is saved on this device. Fetch the page for comparison; nothing will be retried automatically."
        } catch FiestaBoardError.unknownMutationOutcome {
            remoteStatus = .unknownOutcome
            message = "The save result is unknown. Your local draft is safe. Read back the server page before another save."
        } catch {
            // Explicit transport errors establish no accepted page write. Unexpected thrown errors
            // conservatively require readback instead of enabling a duplicate request.
            remoteStatus = error is FiestaBoardError ? .idle : .unknownOutcome
            message = "Server save failed. Your local draft is safe. \(error.localizedDescription)"
        }
    }

    public func fetchRemoteComparison() async {
        guard canFetchRemote, let fetch = remote?.fetch else { return }
        let prior = remoteStatus
        remoteStatus = .reading
        invalidateEvaluation()
        do {
            let data = try await fetch()
            let document = try PageDocument(data: data)
            remoteComparisonData = data
            remoteComparisonText = String(decoding: try document.serializedData(), as: UTF8.self)
            remoteStatus = .comparison
            message = "Fetched server content for comparison. Your editor and original revision are unchanged. Reload only when you choose."
        } catch {
            await preserveForConnectionLoss(error)
            remoteStatus = prior
            message = "Could not read the server page. Your local work is unchanged. \(error.localizedDescription)"
        }
    }

    public func reloadComparedRemote() async {
        guard !editingFrozen, !isSaving, let data = remoteComparisonData else { return }
        isPreparingRemoteSave = true
        guard await saveDraft() else { isPreparingRemoteSave = false; return }
        defer { isPreparingRemoteSave = false }
        do {
            try session.adoptServerDocument(data)
            recoveryPreservationBarrier = session.document
            remoteComparisonData = nil; remoteComparisonText = nil
            remoteStatus = .idle
            invalidateEvaluation()
            message = "Reloaded the compared server page and cleared undo history. Your prior edited draft remains saved on this device until you explicitly save a new local draft."
        } catch { message = error.localizedDescription }
    }

    public func evaluate(preview wantsPreview: Bool) async {
        guard canEvaluate, let target = selectedTarget, let remote else { return }
        evaluationGeneration &+= 1
        let generation = evaluationGeneration
        let revision = session.revision
        isEvaluating = true
        defer { if generation == evaluationGeneration { isEvaluating = false } }
        do {
            let data = try session.document.evaluationData(boardID: target.boardID, preview: wantsPreview)
            if wantsPreview, let run = remote.preview {
                let result = try await run(data, target)
                guard generation == evaluationGeneration, session.revision == revision, selectedTarget == target else { return }
                preview = result
            } else if let run = remote.validate {
                let result = try await run(data, target)
                guard generation == evaluationGeneration, session.revision == revision, selectedTarget == target else { return }
                validation = result
            }
        } catch {
            await preserveForConnectionLoss(error)
            guard generation == evaluationGeneration, session.revision == revision, selectedTarget == target else { return }
            message = "Evaluation unavailable: \(error.localizedDescription)"
        }
    }

    /// A read can invalidate authentication and remove the sheet. Its suspended operation retains
    /// this coordinator, allowing the latest edits (including edits after a stale preview started)
    /// to be checkpointed before returning. A stale result is not itself evidence of connection
    /// loss, and acknowledged/reloaded server content must not overwrite the prior recovery copy.
    private func preserveForConnectionLoss(_ error: any Error) async {
        guard !editingEnded, let error = error as? FiestaBoardError,
              error == .unauthenticated || error == .staleSession,
              session.document != recoveryPreservationBarrier else { return }
        do {
            // This is an emergency recovery copy, not the user's explicit local-save checkpoint.
            // Leave local dirty bookkeeping intact even after a successful preservation write.
            let captured = session.document
            let capturedBaseline = session.baseline
            try await draftStore.save(session.snapshot(identity: identity))
            // A concurrent explicit reload/checkpoint owns its newer barrier. An emergency
            // write must not reset that choice when its actor continuation resumes later.
            if session.document == captured, session.baseline == capturedBaseline {
                recoveryPreservationBarrier = captured
            }
        } catch {
            message = "Connection ended and the recovery draft could not be saved: \(error.localizedDescription)"
        }
    }

}
