import Foundation
import Combine
import FiestaBoardKit

public struct CollectionEditorActions: Sendable {
    public let save: @MainActor @Sendable (CollectionInput, String?) async throws -> PageCollection
    public let delete: @MainActor @Sendable (String) async throws -> Void
    public let compare: @MainActor @Sendable () async throws -> PageCollection?
    public init(save: @escaping @MainActor @Sendable (CollectionInput, String?) async throws -> PageCollection,
                delete: @escaping @MainActor @Sendable (String) async throws -> Void,
                compare: @escaping @MainActor @Sendable () async throws -> PageCollection?) {
        self.save = save; self.delete = delete; self.compare = compare
    }
}

@MainActor public final class CollectionEditorModel: ObservableObject {
    public let deploymentID: String
    public let isSimulated: Bool
    @Published public private(set) var draft: CollectionDraft
    @Published public private(set) var baseline: PageCollection?
    @Published public private(set) var status: CollectionEditorStatus = .idle
    @Published public private(set) var message: String?
    @Published public private(set) var comparison: PageCollection?
    @Published public private(set) var recovery: [CollectionDraftCheckpoint] = []
    private let archive: CollectionDraftArchive
    private let actions: CollectionEditorActions
    private let writeAccess: Bool
    private var sourceSupportsEditing: Bool
    private var checkpointID = UUID()
    private var recoveryChecked = false
    private var preservationBarrier: CollectionDraft?
    public init(deploymentID: String, collection: PageCollection?, canSave: Bool, isSimulated: Bool = false,
                archive: CollectionDraftArchive, actions: CollectionEditorActions) {
        self.deploymentID = deploymentID; baseline = collection; draft = CollectionDraft(collection: collection)
        sourceSupportsEditing = collection?.supportsEditing ?? true
        writeAccess = canSave; self.isSimulated = isSimulated; self.archive = archive; self.actions = actions
    }
    public var collectionID: String? { baseline?.id }
    public var originalRevision: String? { baseline?.revision }
    public var hasChanges: Bool { draft != CollectionDraft(collection: baseline) }
    public var canRecover: Bool { !recovery.isEmpty }
    public var editingFrozen: Bool { [.saving, .deleting, .reading, .ended].contains(status) }
    public var supportsEditing: Bool {
        sourceSupportsEditing && CollectionSelectionMode(rawValue: draft.selectionMode) != nil &&
        (baseline == nil || (baseline?.editProtocol == "collection-revision-v1" && !(originalRevision ?? "").isEmpty))
    }
    public var validatedInput: CollectionInput? { try? draft.input() }
    public var canSave: Bool { writeAccess && supportsEditing && status == .idle && hasChanges && validatedInput != nil }
    public var canDelete: Bool { writeAccess && supportsEditing && status == .idle && originalRevision != nil }
    public var canCompare: Bool { !editingFrozen && status != .missing }
    public var disabledReason: String? {
        if !supportsEditing { return "This collection's mode or revision protocol is unsupported. Its known fields remain available to inspect and copy." }
        if !writeAccess { return "Collection storage requires the audited server version, supported revision protocol, and session write opt-in." }
        switch status {
        case .conflict: return "The collection changed. Compare server content, then explicitly adopt it before another write."
        case .unknownOutcome: return baseline == nil ? "Creation may have succeeded. Review the collection list before starting a new collection. This draft cannot be resubmitted." : "The result is unknown. Compare server content before another write."
        case .comparison: return "Comparison leaves your original draft unchanged. Adopt the compared content explicitly to continue."
        case .missing: return "This collection is missing. Preserve or copy your draft and close this editor."
        case .ended: return "This editing session has ended."
        default: return nil
        }
    }
    public var validationMessage: String? {
        guard supportsEditing, validatedInput == nil else { return nil }
        return "Use a name of 1–100 Unicode scalars and unique member pages. Intervals must be 5–86400 seconds; polling must be 2–600 seconds. Rules and fallback must reference member pages."
    }
    public var localCopyText: String {
        let snapshot = checkpoint()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(snapshot)).map { String(decoding: $0, as: UTF8.self) } ?? "Draft unavailable"
    }
    public var comparisonText: String? {
        guard let comparison else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(comparison)).map { String(decoding: $0, as: UTF8.self) }
    }
    public func edit(_ operation: (inout CollectionDraft) -> Void) {
        guard !editingFrozen, supportsEditing else { return }
        let previousMode = draft.selectionMode
        operation(&draft)
        if previousMode == "variable" || draft.selectionMode == "variable" { draft.hasVariableConfig = true }
        if previousMode == "random" || draft.selectionMode == "random" { draft.hasRandomConfig = true }
        message = nil
        // A no-op after explicit server adoption must retain the pre-adoption copy.
        guard preservationBarrier != draft else { return }
        preservationBarrier = nil
        if hasChanges || status != .idle { _ = preserve() }
        else {
            // A deliberate full revert must not resurrect an earlier intermediate edit.
            // Only this editor's file is removed; recovered sources and other windows remain.
            do { try archive.remove(checkpointID) }
            catch { message = "Could not reconcile the reverted local draft: \(error.localizedDescription)" }
        }
    }
    public func checkRecovery() {
        guard !recoveryChecked else { return }
        do {
            recovery = try archive.load(deploymentID: deploymentID, collectionID: collectionID).filter { $0.id != checkpointID }
            recoveryChecked = true
        } catch { message = "Could not check local drafts: \(error.localizedDescription)" }
    }
    public func recoverDraft(id: UUID? = nil) {
        guard !editingFrozen, !hasChanges, let value = recovery.first(where: { id == nil || $0.id == id }) else { return }
        baseline = value.baseline; sourceSupportsEditing = value.sourceSupportsEditing; draft = value.draft; checkpointID = UUID()
        // Interrupted dispatched mutations remain uncertain after app termination.
        status = [.saving, .deleting, .reading].contains(value.status) ? .unknownOutcome : value.status
        comparison = nil; recovery.removeAll { $0.id == value.id }
        preservationBarrier = nil
        message = "Recovered the original local draft and revision. Nothing was sent."
        // Recovery copies content into an independently owned file. Saving or discarding
        // this window must never remove the recovery source or another window's work.
        _ = preserve()
    }
    public func dismissRecovery() { recovery = [] }
    @discardableResult public func preserve() -> Bool {
        guard status != .ended else { return true }
        // Explicit adoption leaves the prior local copy intact until deliberate new editing.
        guard preservationBarrier != draft else { return true }
        do { try archive.save(checkpoint()); return true }
        catch { message = "Could not preserve this draft. Copy its text before closing. \(error.localizedDescription)"; return false }
    }
    public func discard() {
        guard !editingFrozen else { return }
        do { try archive.remove(checkpointID); status = .ended }
        catch { message = "Could not remove the local draft: \(error.localizedDescription)" }
    }
    public func closeKeepingDraft() -> Bool {
        guard !editingFrozen else { return false }
        if hasChanges || status != .idle { guard preserve() else { return false } }
        status = .ended; return true
    }
    public func save() async {
        guard canSave, let input = validatedInput else { return }
        guard !Task.isCancelled else { return }
        status = .saving; preservationBarrier = nil
        guard preserve() else { status = .idle; return }
        do {
            let receipt = try await actions.save(input, originalRevision)
            guard receipt.editProtocol == "collection-revision-v1", !(receipt.revision ?? "").isEmpty,
                  CollectionSelectionMode(rawValue: receipt.selectionMode) != nil else { throw FiestaBoardError.unknownMutationOutcome }
            try archive.remove(checkpointID)
            baseline = receipt; sourceSupportsEditing = receipt.supportsEditing; draft = CollectionDraft(collection: receipt); comparison = nil; status = .idle
            preservationBarrier = draft
            message = (isSimulated ? "Simulated: " : "") + "Collection storage acknowledged. Display output is not confirmed; board selection remains a separate action."
        } catch { handle(error, operation: "save") }
    }
    public func delete() async {
        guard canDelete, let revision = originalRevision, !Task.isCancelled else { return }
        status = .deleting; preservationBarrier = nil
        guard preserve() else { status = .idle; return }
        do {
            try await actions.delete(revision)
            try archive.remove(checkpointID); status = .ended
            message = isSimulated ? "Simulated collection deletion acknowledged." : "Collection deletion acknowledged."
        } catch { handle(error, operation: "delete") }
    }
    public func compare() async {
        guard canCompare else { return }
        let previous = status; status = .reading
        do {
            let fetched = try await actions.compare()
            if baseline == nil {
                status = .unknownOutcome
                message = "Review the collection list. A possibly completed creation cannot be retried from this draft."
            } else if let fetched {
                comparison = fetched; status = .comparison
                message = "Server content fetched for comparison. Your draft and original revision are unchanged."
            } else {
                status = .missing; message = "The server collection is missing. Your draft remains available to copy or keep locally."
            }
            _ = preserve()
        } catch {
            switch error {
            case FiestaBoardError.rejected(status: 404): status = .missing
            case FiestaBoardError.unauthenticated, FiestaBoardError.staleSession, FiestaBoardError.staleCollectionContext: status = .unknownOutcome
            default: status = previous
            }
            _ = preserve(); message = "Comparison failed. Your original draft is unchanged. \(error.localizedDescription)"
        }
    }
    public func adoptComparison() {
        guard status == .comparison, let comparison, preserve() else { return }
        baseline = comparison; sourceSupportsEditing = comparison.supportsEditing; draft = CollectionDraft(collection: comparison); self.comparison = nil; status = .idle
        preservationBarrier = draft
        message = "Adopted the compared server revision. Your prior local draft remains preserved."
    }
    private func checkpoint() -> CollectionDraftCheckpoint {
        .init(id: checkpointID, deploymentID: deploymentID, collectionID: collectionID, baseline: baseline, draft: draft, sourceSupportsEditing: sourceSupportsEditing, status: status)
    }
    private func handle(_ error: any Error, operation: String) {
        switch error {
        case FiestaBoardError.collectionConflict: status = .conflict
        case FiestaBoardError.collectionReadbackRequired, FiestaBoardError.unknownMutationOutcome: status = .unknownOutcome
        case FiestaBoardError.rejected(status: 404): status = .missing
        case FiestaBoardError.collectionInUse:
            status = .idle
            message = "This collection is in use. Remove its references in schedules, carousels, or boards before deleting it. Your draft is preserved."
            _ = preserve(); return
        case FiestaBoardError.unauthenticated, FiestaBoardError.staleSession, FiestaBoardError.staleCollectionContext:
            status = .unknownOutcome
        case is CancellationError: status = .unknownOutcome
        case is FiestaBoardError: status = .idle
        default: status = .unknownOutcome
        }
        _ = preserve()
        message = "Collection \(operation) did not receive an acknowledgement. Your local draft is preserved. \(error.localizedDescription)"
    }
}
