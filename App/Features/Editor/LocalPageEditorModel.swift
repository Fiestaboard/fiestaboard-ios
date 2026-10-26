import Foundation
import Combine
import FiestaBoardDocuments

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

    public init(rawDocumentData: Data, identity: DraftIdentity, draftStore: LocalDraftStore) throws {
        self.identity = identity
        self.draftStore = draftStore
        session = try DocumentEditingSession(data: rawDocumentData)
    }
    public var name: String { session.document.name ?? "" }
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
    public func undo() { mutate { try $0.undo() } }
    public func redo() { mutate { try $0.redo() } }
    private func mutate(_ operation: (inout DocumentEditingSession) throws -> Void) {
        do { try operation(&session); message = nil }
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
        guard let recovery else { return }
        do {
            // Do not replace edits already made while recovery lookup was running.
            guard !session.hasUnsavedChanges else {
                message = "Undo your unsaved changes before recovering this draft."
                return
            }
            try session.recover(recovery)
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
}
