import Foundation
import Combine
import FiestaBoardKit

public struct PageEditingContext: Sendable, Equatable {
    public let pageID: String
    public let deployment: DeploymentURL
    public let scope: VerifiedConnectionScope
    public let originalRevision: String?
    public let editProtocol: String?
    fileprivate let supportsPageEditing: Bool
    fileprivate let supportsFlexibleEditing: Bool
    fileprivate let generation: UInt64
    fileprivate let documentID: UUID
}
public enum PageEditingAccess: Sendable, Equatable {
    case enabled, simulated, disabled(String)
    public var canSave: Bool { if case .disabled = self { return false }; return true }
    public var reason: String {
        switch self {
        case .enabled: "Page storage is enabled for this session. Saving does not directly send to hardware."
        case .simulated: "Simulated page storage; changes remain in memory."
        case .disabled(let reason): reason
        }
    }
}
public enum PageLibraryPhase: Equatable, Sendable {
    case idle, working, completed(String), reviewRequired(String), reviewed(String), failed(String)
    public var message: String? {
        switch self {
        case .idle, .working: nil
        case .completed(let text), .reviewRequired(let text), .reviewed(let text), .failed(let text): text
        }
    }
}
/// Retained per deployment so dismissing a sheet cannot replay an ambiguous operation.
@MainActor public final class PageLibraryState: ObservableObject {
    public let deployment: DeploymentURL
    @Published public var name = ""
    @Published public var isPanel = false
    @Published public var rows = 8
    @Published public var columns = 16
    @Published public fileprivate(set) var phase: PageLibraryPhase = .idle
    @Published public fileprivate(set) var capability = PageManagementCapability(canCreate: false, canDelete: false)
    @Published public fileprivate(set) var deletion: PageDeletionContext?
    fileprivate var deletionGeneration: UInt64 = 0
    fileprivate var deletionWriteGeneration: UInt64 = 0
    fileprivate var blocked = false
    fileprivate var deletionRecoveryEpochs: [String: UInt64] = [:]
    public var busy: Bool { phase == .working }
    /// The "Page created" note belongs to the create sheet; clear it once the
    /// sheet (or the editor it became) closes, so the Pages list never keeps a
    /// stale "open its editor" instruction after the page was saved.
    public func dismissCompletion() { if case .completed = phase { phase = .idle } }
    public var needsReview: Bool { blocked }
    public var canCreate: Bool { capability.canCreate && !busy && !blocked }
    public var canDelete: Bool { capability.canDelete && !busy && !blocked }
    fileprivate init(deployment: DeploymentURL) { self.deployment = deployment }
}
private struct PageIdentity: Hashable { let deployment: DeploymentURL; let id: String }
public struct PageDocumentSnapshot: Sendable {
    public let scope: VerifiedConnectionScope
    public let id: String
    public let deployment: DeploymentURL
    public let data: Data
    public let context: PageEditingContext
    public let editingAccess: PageEditingAccess
    public let incompatibleReferenceCount: Int
}

public enum RemoteLogoutState: Sendable, Equatable { case pending, succeeded, failed }
public struct LogoutNotice: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let deployment: DeploymentURL
    public let state: RemoteLogoutState
    public let cleanupPending: Bool
    public var message: String {
        let suffix = cleanupPending ? " Saved sign-in could not be removed from this device; try forgetting it again." : ""
        switch state {
        case .pending: return "Signing out of \(deployment.description)…" + suffix
        case .succeeded: return "Server sign-out confirmed for \(deployment.description)." + suffix
        case .failed: return "Server sign-out could not be confirmed for \(deployment.description). Sign out in its web interface if needed." + suffix
        }
    }
}
public enum ActionPayload: Sendable { case text(String), page(String), configuration(BoardPatch), restore }
/// A confirmation binds the exact payload to the deployment, board and current UI generation.
public struct PreparedAction: Identifiable, Sendable {
    public let id = UUID()
    public let target: BoardTarget
    public let payload: ActionPayload
    public let boardName: String
    public let isDemo: Bool
    let generation: UInt64
    let defaultContext: BoardDefaultContext?
    let defaultCapability: DefaultPageWriteCapability
}

// Combine keeps this draft buildable where compiler macro sandbox execution is unavailable.
@MainActor public final class BoardStore: ObservableObject {
    @Published public private(set) var pageLibrary: PageLibraryState?
    private var pageLibraryObservation: AnyCancellable?
    private var pageLibraryEpoch: UInt64 = 0
    private var pageLibraries: [DeploymentURL: PageLibraryState] = [:]
    @Published public private(set) var status: ConnectionStatus?
    @Published public private(set) var boards: [BoardSummary] = []
    @Published public private(set) var pages: [Page] = []
    @Published public private(set) var scheduleList: ScheduleList?
    @Published public private(set) var scheduleTarget: BoardTarget?
    @Published public private(set) var schedulesLoading = false
    @Published public private(set) var scheduleMessage: String?
    private var scheduleTask: Task<Void, Never>?
    private var scheduleRequest = UUID()
    @Published public private(set) var collections: [PageCollection] = []
    @Published public private(set) var collectionsLoading = false
    @Published public private(set) var collectionMessage: String?
    private var collectionListTask: Task<Void, Never>?
    private var collectionListRequest = UUID()
    private var collectionContexts: [UUID: CollectionEditingContext] = [:]
    private var collectionDocumentTokens: [String: UUID] = [:]
    private var collectionMutating: Set<CollectionIdentity> = []
    private var collectionReadbacks: Set<CollectionIdentity> = []
    private var consumedCollectionCreations: Set<UUID> = []
    private var collectionCreationReviews: Set<DeploymentURL> = []
    private var collectionWriteGenerations: [CollectionIdentity: UInt64] = [:]
    private var collectionListGenerations: [DeploymentURL: UInt64] = [:]
    @Published public private(set) var defaultPageContext: BoardDefaultContext?
    @Published public private(set) var defaultPageCapability: DefaultPageWriteCapability = .unavailable
    public var canChangeDefaultPage: Bool {
        guard canWrite else { return false }
        switch defaultPageCapability {
        case .conditional: return defaultPageContext?.target == target
        case .legacyUnconditioned, .simulated: return true
        case .unavailable: return false
        }
    }
    @Published public private(set) var board: BoardDetail?
    @Published public private(set) var selectedBoardID: String?
    @Published public private(set) var message: String?
    @Published public private(set) var remoteLogoutState: RemoteLogoutState?
    @Published public private(set) var logoutNotices: [LogoutNotice] = []
    @Published public private(set) var connecting = false
    @Published public private(set) var refreshing = false
    @Published private var readbackTargets: Set<BoardTarget> = []
    public var needsReadback: Bool { target.map { readbackTargets.contains($0) } ?? false }
    @Published public private(set) var connectionLabel = "Disconnected"
    private var generation: UInt64 = 0
    private var pageSessionOptedIn = false
    private var pageContexts: [String: UUID] = [:]
    private var savingPages: Set<PageIdentity> = []
    private var pageReadbacks: Set<PageIdentity> = []
    private var pageWriteGenerations: [PageIdentity: UInt64] = [:]
    private var service: (any FiestaBoardService)?
    private var connectionTask: Task<Void, Never>?
    private var retirementTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    @Published private var inFlight: Set<BoardTarget> = []
    private var usedActions: Set<UUID> = []
    public var commandBusy: Bool { target.map { inFlight.contains($0) } ?? false }
    public var canWrite: Bool {
        board != nil && status != nil && status?.access != .readOnly && target != nil && !connecting && !refreshing && !commandBusy && !needsReadback && pageLibrary?.busy != true && pageLibrary?.needsReview != true
    }
    public var boardActionDisabledReason: ActionDisabledReason? {
        guard let status else { return .disconnected }
        guard selectedBoardID != nil else { return .noDisplay }
        if connecting || refreshing || commandBusy || pageLibrary?.busy == true { return .busy }
        if needsReadback || pageLibrary?.needsReview == true { return .readbackRequired }
        guard board != nil else { return .readbackRequired }
        if status.isDemo { return nil }
        if let reason = CapabilityPolicy.boardActionDisabledReason(version: status.version.runningVersion,
            isDev: status.version.isDev, optedIn: pageSessionOptedIn) { return reason }
        return status.access == .readOnly ? .unsupportedOperation : nil
    }
    public var pageManagementDisabledReason: ActionDisabledReason? {
        guard let status else { return .disconnected }
        if connecting || pageLibrary?.busy == true { return .busy }
        if pageLibrary?.needsReview == true { return .readbackRequired }
        if status.isDemo { return nil }
        if let reason = CapabilityPolicy.pageManagementDisabledReason(version: status.version.runningVersion,
            isDev: status.version.isDev, optedIn: pageSessionOptedIn) { return reason }
        return pageLibrary?.capability.canCreate == true || pageLibrary?.capability.canDelete == true ? nil : .unsupportedOperation
    }
    public func pageDeletionDisabledReason(for page: Page) -> ActionDisabledReason? {
        guard let status, let service else { return .disconnected }
        let eligibility = CapabilityPolicy.pageDeletionDisabledReason(page, version: status.version.runningVersion,
            isDev: status.version.isDev, optedIn: pageSessionOptedIn, isSimulated: status.isDemo)
        if let eligibility, eligibility != .changesDisabled { return eligibility }
        let identity = PageIdentity(deployment: service.deployment, id: page.id)
        if connecting || pageLibrary?.busy == true || savingPages.contains(identity) { return .busy }
        if pageLibrary?.needsReview == true || pageReadbacks.contains(identity) { return .readbackRequired }
        if let eligibility { return eligibility }
        return pageLibrary?.canDelete == true ? nil : .unsupportedOperation
    }
    public func webEditorURL(pageID: String) -> URL? {
        guard let service, let status, !connecting else { return nil }
        return try? service.deployment.webEditorURL(pageID: pageID, isDemo: status.isDemo)
    }
    private var target: BoardTarget? {
        guard let service, let id = selectedBoardID else { return nil }
        return try? BoardTarget(deployment: service.deployment, boardID: id)
    }
    public init() {}
    var hasRetainedService: Bool { service != nil }

    @discardableResult public func connect(_ next: any FiestaBoardService, allowCandidateWrites: Bool = false,
                                           username: String = "", password: String = "", preferredBoardID: String? = nil) -> Task<Void, Never> {
        let retirement = retireService()
        resetConnection()
        service = next
        connectionLabel = next.isDemo ? "Demo · simulated" : next.deployment.description
        connecting = true
        let token = generation
        let task = Task { [weak self] in
            guard let self else { return }
            await retirement?.value
            guard valid(token) else { return }
            do {
                let auth = try await next.authStatus()
                guard valid(token) else { return }
                guard !auth.setupRequired else { throw StoreError.setupRequired }
                if auth.enabled && !auth.authenticated {
                    guard !username.isEmpty && !password.isEmpty else { throw FiestaBoardError.unauthenticated }
                    _ = try await next.login(username: username, password: password)
                }
                guard valid(token) else { return }
                let result = try await next.connect(allowCandidateWrites: allowCandidateWrites)
                guard valid(token) else { return }
                let list = try await next.boards()
                guard valid(token) else { return }
                pageSessionOptedIn = allowCandidateWrites || result.isDemo
                status = result; boards = list
                let libraryState = pageLibraries[next.deployment] ?? PageLibraryState(deployment: next.deployment)
                pageLibraries[next.deployment] = libraryState
                pageLibrary = libraryState
                pageLibraryObservation = libraryState.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
                let capability = await next.pageManagementCapability()
                guard valid(token) else { return }
                libraryState.capability = capability
                // Initial selection loads detail without treating it as explicit recovery from an unknown command.
                selectedBoardID = list.first(where: { $0.id == preferredBoardID })?.id ?? list.first?.id
                do {
                    let library = try await next.pages()
                    guard valid(token) else { return }
                    pages = library
                } catch {
                    guard valid(token) else { return }
                    if handleAuthenticationLoss(error) { return }
                    message = "The library could not be loaded. " + safeDescription(error)
                }
                if let target {
                    do {
                        let detail = try await next.board(target)
                        guard valid(token) else { return }
                        board = detail
                        await loadDefaultContext(next, target: target, token: token)
                        // An ambiguous command barrier survives reconnect; only explicit refresh clears it.
                    } catch {
                        guard valid(token) else { return }
                        if handleAuthenticationLoss(error) { return }
                        readbackTargets.insert(target)
                        message = "Display details could not be loaded. Refresh before using controls. " + safeDescription(error)
                    }
                }
            } catch {
                guard valid(token) else { return }
                if !handleAuthenticationLoss(error) { message = safeDescription(error) }
            }
            if valid(token) { connecting = false }
        }
        connectionTask = task
        return task
    }

    @discardableResult public func reconnect(allowCandidateWrites: Bool, preferredBoardID: String? = nil) -> Task<Void, Never> {
        guard let service else { return Task {} }
        // Retire UI contexts without clearing this actor's valid memory cookie.
        let preferred = preferredBoardID ?? selectedBoardID
        self.service = nil
        return connect(service, allowCandidateWrites: allowCandidateWrites, preferredBoardID: preferred)
    }

    private func retireService() -> Task<Void, Never>? {
        guard let old = service else { return retirementTask }
        let previous = retirementTask
        let task = Task { await previous?.value; await old.disconnect() }
        retirementTask = task
        return task
    }
    public func disconnect() {
        _ = retireService()
        resetConnection()
    }
    public func waitForSessionCleanup() async { await retirementTask?.value }
    private func resetConnection() {
        generation &+= 1
        clearSchedules()
        pageLibraryObservation = nil; pageLibrary = nil; pageLibraryEpoch &+= 1
        connectionTask?.cancel(); refreshTask?.cancel(); commandTask?.cancel(); collectionListTask?.cancel()
        connectionTask = nil; refreshTask = nil; commandTask = nil
        service = nil; status = nil; boards = []; pages = []; board = nil; defaultPageContext = nil; defaultPageCapability = .unavailable; selectedBoardID = nil
        connecting = false; refreshing = false; message = nil; remoteLogoutState = nil
        connectionLabel = "Disconnected"; usedActions = []; pageContexts = [:]; pageSessionOptedIn = false
        collections = []; collectionMessage = nil; collectionsLoading = false
        collectionContexts = [:]; collectionDocumentTokens = [:]
        collectionListTask = nil; collectionListRequest = UUID()
    }

    /// Drops the local session immediately; the captured old service revokes its session separately.
    @discardableResult public func logout() -> Task<Void, Never> {
        let old = service
        resetConnection()
        guard let old else { return Task {} }
        let token = generation
        let server = old.deployment.description
        let noticeID = UUID()
        logoutNotices.append(LogoutNotice(id: noticeID, deployment: old.deployment, state: .pending, cleanupPending: false))
        remoteLogoutState = .pending
        message = "Disconnected locally. Signing out of \(server)…"
        return Task { [weak self] in
            do {
                try await old.logout()
                let persistence = await old.sessionPersistenceState()
                guard let self else { return }
                updateLogoutNotice(noticeID, state: .succeeded, cleanupPending: persistence.cleanupPending)
                guard generation == token else { return }
                remoteLogoutState = .succeeded
                message = "Disconnected locally. Server sign-out confirmed for \(server)."
            } catch {
                let persistence = await old.sessionPersistenceState()
                guard let self else { return }
                updateLogoutNotice(noticeID, state: .failed, cleanupPending: persistence.cleanupPending)
                guard generation == token else { return }
                remoteLogoutState = .failed
                message = "Disconnected locally. Server sign-out could not be confirmed for \(server); the server session may still be active. Sign out in the server’s web interface if needed."
            }
        }
    }

    private func updateLogoutNotice(_ id: UUID, state: RemoteLogoutState, cleanupPending: Bool) {
        guard let index = logoutNotices.firstIndex(where: { $0.id == id }) else { return }
        logoutNotices[index] = LogoutNotice(id: id, deployment: logoutNotices[index].deployment, state: state, cleanupPending: cleanupPending)
    }

    @discardableResult public func selectBoard(_ id: String) -> Task<Void, Never> {
        guard boards.contains(where: { $0.id == id }), !connecting else { return Task {} }
        generation &+= 1
        clearSchedules()
        refreshTask?.cancel(); commandTask?.cancel()
        selectedBoardID = id; board = nil; defaultPageContext = nil; message = nil; usedActions = []
        return refresh()
    }

    @discardableResult public func refresh() -> Task<Void, Never> {
        guard let service, status != nil, let target, !commandBusy else { return Task {} }
        refreshTask?.cancel()
        let token = generation
        refreshing = true
        defaultPageContext = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await service.board(target)
                guard valid(token) else { return }
                acceptSnapshot(detail); readbackTargets.remove(target)
                await loadDefaultContext(service, target: target, token: token)
            } catch {
                guard valid(token) else { return }
                if !handleAuthenticationLoss(error) { message = safeDescription(error) }
            }
            if valid(token) { refreshing = false }
        }
        refreshTask = task
        return task
    }

    private func loadDefaultContext(_ service: any FiestaBoardService, target: BoardTarget, token: UInt64) async {
        let capability = await service.defaultPageWriteCapability()
        guard valid(token), self.target == target else { return }
        defaultPageCapability = capability
        guard capability == .conditional else { defaultPageContext = nil; return }
        do {
            let context = try await service.readDefaultPage(on: target)
            guard valid(token), self.target == target else { return }
            defaultPageContext = context
        } catch {
            guard valid(token) else { return }
            defaultPageContext = nil
            _ = handleAuthenticationLoss(error)
        }
    }

    /// A failed optional library read can be retried without replacing authentication or document contexts.
    @discardableResult public func refreshLibrary() -> Task<Void, Never> {
        guard let service, status != nil, !connecting, pageLibrary?.busy != true else { return Task {} }
        let token = generation
        let epoch = pageLibraryEpoch
        return Task { [weak self] in
            guard let self else { return }
            do {
                let library = try await service.pages()
                guard valid(token), epoch == pageLibraryEpoch else { return }; pages = library
            } catch {
                guard valid(token) else { return }
                if !handleAuthenticationLoss(error) { message = "The library could not be loaded. " + safeDescription(error) }
            }
        }
    }

    /// Bind local editor input to this connection; a late reply cannot become another server's document.
    public func loadPageDocument(id: String) async throws -> PageDocumentSnapshot {
        guard let service, status != nil, !connecting, pages.contains(where: { $0.id == id }) else {
            throw FiestaBoardError.invalidTarget
        }
        let token = generation
        let deployment = service.deployment
        let identity = PageIdentity(deployment: deployment, id: id)
        let writeGeneration = pageWriteGenerations[identity, default: 0]
        guard !savingPages.contains(identity) else { throw FiestaBoardError.pageReadbackRequired }
        do {
            let document = try await service.scopedPageDocument(id: id)
            let data = document.data
            guard document.scope.deployment == deployment else { throw FiestaBoardError.staleSession }
            guard token == generation, self.service?.deployment == deployment else { throw FiestaBoardError.staleSession }
            guard writeGeneration == pageWriteGenerations[identity, default: 0] else { throw FiestaBoardError.stalePageContext }
            try Task.checkCancellation()
            guard !savingPages.contains(identity) else { throw FiestaBoardError.pageReadbackRequired }
            pageReadbacks.remove(identity)
            return try acceptPageDocument(id: id, deployment: deployment, scope: document.scope, data: data)
        } catch {
            guard token == generation else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error)
            throw error
        }
    }

    public func readbackPage(context: PageEditingContext) async throws -> PageDocumentSnapshot {
        try requirePageContext(context)
        let snapshot = try await loadPageDocument(id: context.pageID)
        guard snapshot.scope == context.scope else { throw FiestaBoardError.staleSession }
        return snapshot
    }
    /// Explicit, connection-scoped page storage. No save replay or hidden revision refresh.
    public func savePage(patch: PageSavePatch, context: PageEditingContext) async throws -> PageDocumentSnapshot {
        try requirePageContext(context)
        let identity = PageIdentity(deployment: context.deployment, id: context.pageID)
        guard !savingPages.contains(identity), !pageReadbacks.contains(identity) else { throw FiestaBoardError.pageReadbackRequired }
        guard pageEditingAccess(context: context).canSave, let service else { throw FiestaBoardError.pageWritesDisabled }
        try patch.validate()
        pageWriteGenerations[identity, default: 0] &+= 1
        pageLibraryEpoch &+= 1
        savingPages.insert(identity); pageReadbacks.insert(identity)
        defer { savingPages.remove(identity) }
        do {
            let receipt = try await service.savePage(id: context.pageID, patch: patch)
            try requirePageContext(context)
            pageReadbacks.remove(identity); savingPages.remove(identity)
            return try acceptPageDocument(id: context.pageID, deployment: context.deployment, scope: context.scope, data: receipt.pageData, incompatibleReferenceCount: receipt.incompatibleReferenceCount)
        } catch {
            guard context.generation == generation else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error)
            if !(error is CancellationError) {
                switch error as? FiestaBoardError {
                case .unknownMutationOutcome, .pageConflict, .staleSession, .stalePageContext: break
                default: pageReadbacks.remove(identity)
                }
            }
            throw error
        }
    }
    public func pageEditingAccess(context: PageEditingContext) -> PageEditingAccess {
        do { try requirePageContext(context) }
        catch { return .disabled(error.localizedDescription) }
        let identity = PageIdentity(deployment: context.deployment, id: context.pageID)
        guard !savingPages.contains(identity), !pageReadbacks.contains(identity) else { return .disabled(FiestaBoardError.pageReadbackRequired.localizedDescription) }
        guard pageSessionOptedIn, context.supportsPageEditing, context.editProtocol == "page-revision-v1", context.originalRevision?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .disabled(FiestaBoardError.pageWritesDisabled.localizedDescription)
        }
        return status?.isDemo == true ? .simulated : .enabled
    }
    public func validatePage(requestData: Data, context: PageEditingContext, target: BoardTarget) async throws -> TemplateValidationResult {
        try requirePageContext(context); try requirePreviewTarget(target)
        guard let service else { throw FiestaBoardError.staleSession }
        do {
            let result = try await service.validatePage(requestData: requestData, target: target)
            try requirePageContext(context); try requirePreviewTarget(target)
            return result
        } catch {
            guard context.generation == generation else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error); throw error
        }
    }
    public func previewPage(requestData: Data, context: PageEditingContext, target: BoardTarget) async throws -> TemplatePreviewResult {
        try requirePageContext(context); try requirePreviewTarget(target)
        guard let service else { throw FiestaBoardError.staleSession }
        do {
            let result = try await service.previewPage(requestData: requestData, target: target)
            try requirePageContext(context); try requirePreviewTarget(target)
            return result
        } catch {
            guard context.generation == generation else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error); throw error
        }
    }
    public func previewFlexiblePage(requestData: Data, context: PageEditingContext, target: BoardTarget) async throws -> FlexiblePreviewResult {
        try requirePageContext(context); try requirePreviewTarget(target)
        guard context.supportsFlexibleEditing else { throw FiestaBoardError.previewUnsupported }
        guard let service else { throw FiestaBoardError.staleSession }
        do {
            let result = try await service.previewFlexiblePage(requestData: requestData, target: target)
            try requirePageContext(context); try requirePreviewTarget(target)
            return result
        } catch {
            guard context.generation == generation else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error); throw error
        }
    }
    private func requirePageContext(_ context: PageEditingContext) throws {
        guard context.generation == generation, !connecting, status != nil,
              service?.deployment == context.deployment else { throw FiestaBoardError.staleSession }
        guard pageContexts[context.pageID] == context.documentID else { throw FiestaBoardError.stalePageContext }
        try Task.checkCancellation()
    }
    private func requirePreviewTarget(_ target: BoardTarget) throws {
        guard target.deployment == service?.deployment, boards.contains(where: { $0.id == target.boardID }) else { throw FiestaBoardError.invalidTarget }
    }
    private func acceptPageDocument(id: String, deployment: DeploymentURL, scope: VerifiedConnectionScope, data: Data, incompatibleReferenceCount: Int = 0) throws -> PageDocumentSnapshot {
        let page = try JSONDecoder().decode(Page.self, from: data)
        guard page.id == id else { throw FiestaBoardError.invalidResponse }
        let context = PageEditingContext(pageID: id, deployment: deployment, scope: scope, originalRevision: page.revision,
                                         editProtocol: page.editProtocol, supportsPageEditing: CapabilityPolicy.supportsEditableDocument(page, version: status?.version.runningVersion, isDev: status?.version.isDev ?? true), supportsFlexibleEditing: CapabilityPolicy.supportsFlexibleDocument(page), generation: generation, documentID: UUID())
        pageContexts[id] = context.documentID
        if let index = pages.firstIndex(where: { $0.id == id }) { pages[index] = page }
        return PageDocumentSnapshot(scope: scope, id: id, deployment: deployment, data: data, context: context, editingAccess: pageEditingAccess(context: context), incompatibleReferenceCount: incompatibleReferenceCount)
    }

    public func prepare(_ payload: ActionPayload) -> PreparedAction? {
        guard canWrite, let target, let summary = boards.first(where: { $0.id == target.boardID }) else { return nil }
        switch payload {
        case .text(let value): guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        case .page(let id): guard pages.contains(where: { $0.id == id }) else { return nil }
        case .configuration(let patch):
            guard (try? patch.validate()) != nil else { return nil }
            if patch.defaultPage != .omit {
                guard canChangeDefaultPage, patch.paused == nil, patch.scheduleEnabled == nil, patch.autoRestore == nil else { return nil }
            }
            if case .set(let id) = patch.defaultPage, !pages.contains(where: { $0.id == id }) { return nil }
        case .restore: break
        }
        return PreparedAction(target: target, payload: payload, boardName: summary.name,
                              isDemo: status?.isDemo == true, generation: generation, defaultContext: defaultPageContext, defaultCapability: defaultPageCapability)
    }

    @discardableResult public func confirm(_ action: PreparedAction) -> Task<Void, Never> {
        guard canWrite, action.generation == generation, action.target == target,
              !usedActions.contains(action.id), let service else { return Task {} }
        usedActions.insert(action.id)
        inFlight.insert(action.target)
        readbackTargets.insert(action.target)
        let token = generation
        let task = Task { [weak self] in
            guard let self else { return }
            defer { inFlight.remove(action.target) }
            do {
                let receipt: String
                switch action.payload {
                case .text(let value): receipt = Self.describe(try await service.sendText(value, to: action.target), simulated: action.isDemo)
                case .page(let id): receipt = Self.describe(try await service.selectPage(id: id, on: action.target), simulated: action.isDemo)
                case .configuration(let patch):
                    if patch.defaultPage != .omit {
                        switch action.defaultCapability {
                        case .conditional:
                            guard let context = action.defaultContext else { throw FiestaBoardError.invalidRequestContext }
                            defaultPageContext = nil
                            _ = try await service.updateDefaultPage(patch.defaultPage, context: context)
                        case .legacyUnconditioned, .simulated:
                            _ = try await service.updateBoard(patch, on: action.target)
                        case .unavailable: throw FiestaBoardError.writesDisabled
                        }
                    } else {
                        _ = try await service.updateBoard(patch, on: action.target)
                    }
                    receipt = (action.isDemo ? "Simulated — " : "") + "Board settings updated. Physical output is not verified."
                case .restore:
                    let result = try await service.restoreBoard(action.target)
                    receipt = (action.isDemo ? "Simulated — " : "") + (result.sent
                        ? "Restore write accepted. Physical output is not verified."
                        : "Restore did not send content. The pinned selection was retained.")
                }
                guard valid(token) else { return }
                message = receipt
                // Keep the receipt separate from readback; a failed refresh never upgrades the receipt.
                do {
                    let detail = try await service.board(action.target)
                    guard valid(token) else { return }
                    acceptSnapshot(detail); readbackTargets.remove(action.target)
                } catch {
                    guard valid(token) else { return }
                    readbackTargets.insert(action.target)
                    if !handleAuthenticationLoss(error, preservingReceipt: message) {
                        message = (message ?? "") + " Readback unavailable. Refresh before another action."
                    }
                }
            } catch {
                guard valid(token) else { return }
                if handleAuthenticationLoss(error) { return }
                message = (action.isDemo ? "Simulated — " : "") + safeDescription(error)
                // PATCH setters run in sequence. Even a 400/404/503 can follow an applied field.
                if case .configuration = action.payload {
                    readbackTargets.insert(action.target)
                    message = (message ?? "") + " Refresh before another action; some settings may have changed."
                } else {
                    switch error as? FiestaBoardError {
                    case .unknownMutationOutcome, .partialWrite: readbackTargets.insert(action.target)
                    default: readbackTargets.remove(action.target)
                    }
                }
            }
        }
        commandTask = task
        return task
    }
    private func acceptSnapshot(_ detail: BoardDetail) {
        board = detail
        if let index = boards.firstIndex(where: { $0.id == detail.summary.id }) { boards[index] = detail.summary }
    }
    /// Authentication loss ends this UI session at every request boundary. It also
    /// invalidates prepared actions; a readback failure cannot erase an earlier receipt.
    private func handleAuthenticationLoss(_ error: any Error, preservingReceipt: String? = nil) -> Bool {
        guard let known = error as? FiestaBoardError, known == .unauthenticated || known == .staleSession else { return false }
        let server = connectionLabel
        disconnect()
        let prompt = "Authentication is required for \(server). Use the manual connection form to sign in again."
        message = preservingReceipt.map { $0 + " " + prompt } ?? prompt
        return true
    }
    private func valid(_ token: UInt64) -> Bool { token == generation && !Task.isCancelled }
    private func safeDescription(_ error: any Error) -> String {
        if let known = error as? FiestaBoardError { return known.localizedDescription }
        if let known = error as? StoreError { return known.localizedDescription }
        return "This draft could not complete the request. Refresh to try reading again."
    }
    private static func describe(_ result: MutationResult, simulated: Bool) -> String {
        let prefix = simulated ? "Simulated — " : ""
        let body: String
        switch result.disposition {
        case .accepted: body = "server acknowledged a send. Physical output is not verified."
        case .held: body = "held by the server; no send acknowledged."
        case .notSent: body = "server did not send this message."
        case .selectionStored: body = "selection stored; no send acknowledged."
        }
        return prefix + body + (result.silenced ? " Board is silenced." : "")
            + (result.deliveryFailed ? " Delivery failed." : "")
            + (result.warningCount > 0 ? " Server reported \(result.warningCount) warning(s)." : "")
    }
}
private enum StoreError: LocalizedError {
    case setupRequired
    var errorDescription: String? { "This server requires first-run setup. Complete setup in its web interface, then connect again." }
}

@MainActor extension BoardStore {
    @discardableResult public func refreshCollections() -> Task<Void, Never> {
        collectionListTask?.cancel()
        guard let service, status != nil, !connecting else { return Task {} }
        let session = generation
        let deployment = service.deployment
        let epoch = collectionListGenerations[deployment, default: 0]
        let request = UUID()
        collectionListRequest = request; collectionsLoading = true; collectionMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if collectionListRequest == request { collectionsLoading = false } }
            do {
                let values = try await service.collections()
                guard valid(session), self.service?.deployment == deployment else { return }
                guard epoch == collectionListGenerations[deployment, default: 0],
                      !collectionMutating.contains(where: { $0.deployment == deployment }) else {
                    throw FiestaBoardError.staleCollectionContext
                }
                collections = values
                // This is review evidence, never permission to replay the old POST.
                if collectionReadbacks.contains(.creation(on: deployment)) {
                    collectionCreationReviews.insert(deployment)
                }
            } catch {
                guard valid(session) else { return }
                if !handleAuthenticationLoss(error) { collectionMessage = safeDescription(error) }
            }
        }
        collectionListTask = task
        return task
    }

    public func beginCollectionEditor(id: String?) async throws -> CollectionEditorSnapshot {
        try await loadCollectionEditor(id: id, expectedScope: nil)
    }
    private func loadCollectionEditor(id: String?, expectedScope: VerifiedConnectionScope?) async throws -> CollectionEditorSnapshot {
        guard let service, status != nil, !connecting else { throw FiestaBoardError.staleSession }
        let session = generation
        let deployment = service.deployment
        let identity = id.map { CollectionIdentity(deployment: deployment, id: $0) } ?? .creation(on: deployment)
        guard !collectionMutating.contains(identity) else { throw FiestaBoardError.collectionReadbackRequired }
        if id == nil, collectionReadbacks.contains(identity) {
            guard collectionCreationReviews.contains(deployment) else { throw FiestaBoardError.collectionReadbackRequired }
            try await service.acknowledgeCollectionCreationReview()
            guard valid(session) else { throw FiestaBoardError.staleSession }
            collectionReadbacks.remove(identity); collectionCreationReviews.remove(deployment)
        }
        let epoch = collectionWriteGenerations[identity, default: 0]
        do {
            let document = try await service.scopedCollectionDocument(id: id)
            guard document.scope.deployment == deployment, expectedScope == nil || document.scope == expectedScope else { throw FiestaBoardError.staleSession }
            let value = document.collection
            let library = try await service.pages()
            let access = await service.collectionAccess()
            let verified = try await service.scopedCollectionDocument(id: nil)
            guard verified.scope == document.scope else { throw FiestaBoardError.staleSession }
            guard session == generation, self.service?.deployment == deployment, status != nil else { throw FiestaBoardError.staleSession }
            try Task.checkCancellation()
            guard epoch == collectionWriteGenerations[identity, default: 0], !collectionMutating.contains(identity) else {
                throw FiestaBoardError.staleCollectionContext
            }
            if let id, value?.id != id { throw FiestaBoardError.invalidResponse }
            collectionReadbacks.remove(identity)
            pages = library
            return acceptCollection(value, scope: document.scope, pages: library, access: access)
        } catch {
            guard session == generation else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error)
            throw error
        }
    }

    public func readbackCollection(context: CollectionEditingContext) async throws -> CollectionEditorSnapshot {
        try requireCollectionContext(context, permitConsumedCreate: true)
        guard let service else { throw FiestaBoardError.staleSession }
        try await verifyCollectionOwnership(context, service: service, permitConsumedCreate: true)
        guard let id = context.collectionID else {
            // A list can help a person inspect an uncertain create; it cannot
            // determine which new resource, if any, came from that POST.
            await refreshCollections().value
            throw FiestaBoardError.collectionReadbackRequired
        }
        do { return try await loadCollectionEditor(id: id, expectedScope: context.scope) }
        catch FiestaBoardError.rejected(status: 404) {
            collectionDocumentTokens[id] = nil; collectionContexts[context.documentToken] = nil
            collections.removeAll { $0.id == id }
            collectionReadbacks.remove(CollectionIdentity(deployment: context.deployment, id: id))
            throw FiestaBoardError.rejected(status: 404)
        }
    }

    public func saveCollection(_ input: CollectionInput, expectedRevision: String?, context: CollectionEditingContext) async throws -> CollectionEditorSnapshot {
        try requireCollectionContext(context)
        guard expectedRevision == context.originalRevision else { throw FiestaBoardError.staleCollectionContext }
        guard context.writeAllowed, pageSessionOptedIn, let service else { throw FiestaBoardError.collectionWritesDisabled }
        try input.validate()
        guard input.pageIDs.allSatisfy({ member in pages.contains { $0.id == member } }) else { throw FiestaBoardError.collectionWritesDisabled }
        let identity = collectionIdentity(context)
        try await verifyCollectionOwnership(context, service: service)
        guard !collectionMutating.contains(identity), !collectionReadbacks.contains(identity) else {
            throw FiestaBoardError.collectionReadbackRequired
        }
        collectionMutating.insert(identity); collectionReadbacks.insert(identity)
        collectionCreationReviews.remove(context.deployment)
        bumpCollectionWrite(identity)
        if context.collectionID == nil { consumedCollectionCreations.insert(context.documentToken) }
        defer { collectionMutating.remove(identity); bumpCollectionWrite(identity) }
        do {
            let result: PageCollection
            if let id = context.collectionID {
                guard let expectedRevision, !expectedRevision.isEmpty else { throw FiestaBoardError.collectionWritesDisabled }
                result = try await service.updateCollection(id: id, input: input, expectedRevision: expectedRevision)
            } else {
                result = try await service.createCollection(input)
            }
            try requireCollectionContext(context, permitConsumedCreate: true)
            guard result.editProtocol == "collection-revision-v1", result.revision?.isEmpty == false,
                  result.revision != expectedRevision,
                  context.collectionID == nil || result.id == context.collectionID,
                  result.name == input.name, result.pageIDs == input.pageIDs,
                  result.selectionMode == input.selectionMode.rawValue,
                  result.time == input.time, result.variable == input.variable, result.random == input.random else {
                throw FiestaBoardError.unknownMutationOutcome
            }
            let access = await service.collectionAccess()
            let verified = try await service.scopedCollectionDocument(id: nil)
            guard verified.scope == context.scope else { throw FiestaBoardError.staleSession }
            try requireCollectionContext(context, permitConsumedCreate: true)
            collectionReadbacks.remove(identity)
            collectionContexts[context.documentToken] = nil
            return acceptCollection(result, scope: context.scope, pages: pages, access: access)
        } catch {
            guard context.generation == generation else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error)
            if collectionKnownRefusal(error) {
                collectionReadbacks.remove(identity)
                consumedCollectionCreations.remove(context.documentToken)
            }
            throw error
        }
    }

    public func deleteCollection(expectedRevision: String, context: CollectionEditingContext) async throws {
        try requireCollectionContext(context)
        guard expectedRevision == context.originalRevision else { throw FiestaBoardError.staleCollectionContext }
        guard context.writeAllowed, pageSessionOptedIn, let service, let id = context.collectionID else {
            throw FiestaBoardError.collectionWritesDisabled
        }
        let identity = collectionIdentity(context)
        try await verifyCollectionOwnership(context, service: service)
        guard !collectionMutating.contains(identity), !collectionReadbacks.contains(identity) else {
            throw FiestaBoardError.collectionReadbackRequired
        }
        collectionMutating.insert(identity); collectionReadbacks.insert(identity); bumpCollectionWrite(identity)
        defer { collectionMutating.remove(identity); bumpCollectionWrite(identity) }
        do {
            try await service.deleteCollection(id: id, expectedRevision: expectedRevision)
            let verified = try await service.scopedCollectionDocument(id: nil)
            guard verified.scope == context.scope else { throw FiestaBoardError.staleSession }
            try requireCollectionContext(context)
            collectionReadbacks.remove(identity)
            collectionDocumentTokens[id] = nil; collectionContexts[context.documentToken] = nil
            collections.removeAll { $0.id == id }
        } catch {
            guard context.generation == generation else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error)
            if collectionKnownRefusal(error) { collectionReadbacks.remove(identity) }
            throw error
        }
    }

    private func acceptCollection(_ value: PageCollection?, scope: VerifiedConnectionScope, pages: [Page], access: CollectionWriteAccess) -> CollectionEditorSnapshot {
        let context = CollectionEditingContext(deployment: scope.deployment, scope: scope, generation: generation,
            documentToken: UUID(), collectionID: value?.id, originalRevision: value?.revision,
            writeAllowed: pageSessionOptedIn && access.writesOptedIn && (value.map {
                $0.supportsEditing && $0.editProtocol == "collection-revision-v1"
                    && $0.revision?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            } ?? access.canCreate))
        collectionContexts[context.documentToken] = context
        if let value {
            if let previous = collectionDocumentTokens[value.id] { collectionContexts[previous] = nil }
            collectionDocumentTokens[value.id] = context.documentToken
            if let index = collections.firstIndex(where: { $0.id == value.id }) { collections[index] = value }
            else { collections.append(value) }
        }
        return CollectionEditorSnapshot(context: context, collection: value, pages: pages,
                                        canSave: context.writeAllowed, isDemo: status?.isDemo == true)
    }

    private func verifyCollectionOwnership(_ context: CollectionEditingContext, service: any FiestaBoardService, permitConsumedCreate: Bool = false) async throws {
        do {
            let verified = try await service.scopedCollectionDocument(id: nil)
            try requireCollectionContext(context, permitConsumedCreate: permitConsumedCreate)
            guard verified.scope == context.scope else { throw FiestaBoardError.staleSession }
        } catch {
            if context.generation == generation { _ = handleAuthenticationLoss(error) }
            throw error
        }
    }

    private func requireCollectionSession(_ context: CollectionEditingContext) throws {
        guard context.generation == generation, !connecting, status != nil,
              service?.deployment == context.deployment else { throw FiestaBoardError.staleSession }
        try Task.checkCancellation()
    }
    private func requireCollectionContext(_ context: CollectionEditingContext, permitConsumedCreate: Bool = false) throws {
        try requireCollectionSession(context)
        guard collectionContexts[context.documentToken] == context,
              context.collectionID.map({ collectionDocumentTokens[$0] == context.documentToken }) ?? true else {
            throw FiestaBoardError.staleCollectionContext
        }
        if !permitConsumedCreate, consumedCollectionCreations.contains(context.documentToken) {
            throw FiestaBoardError.collectionReadbackRequired
        }
    }
    private func collectionIdentity(_ context: CollectionEditingContext) -> CollectionIdentity {
        context.collectionID.map { CollectionIdentity(deployment: context.deployment, id: $0) } ?? .creation(on: context.deployment)
    }
    private func bumpCollectionWrite(_ identity: CollectionIdentity) {
        collectionWriteGenerations[identity, default: 0] &+= 1
        collectionListGenerations[identity.deployment, default: 0] &+= 1
    }
    private func collectionKnownRefusal(_ error: any Error) -> Bool {
        switch error as? FiestaBoardError {
        case .collectionInUse, .collectionWritesDisabled, .rejected(status: 400), .rejected(status: 403),
             .rejected(status: 422), .rateLimited: true
        default: false
        }
    }
}

// Page lifecycle operations share the editor's per-page mutation barriers.
extension BoardStore {
    private func requirePageLibrary() throws -> (any FiestaBoardService, PageLibraryState) {
        guard let service, let library = pageLibrary, status != nil, !connecting,
              library.deployment == service.deployment else { throw FiestaBoardError.staleSession }
        guard !library.busy, !library.needsReview else { throw FiestaBoardError.pageReadbackRequired }
        return (service, library)
    }

    /// Creates a page from the library sheet's input, or — with `name`,
    /// `template` and `family` — from a board frame ("Save as page", B9).
    public func createLibraryPage(name: String? = nil, template: [String] = [],
                                  family: PageCreationFamily? = nil) async throws -> String {
        let (service, library) = try requirePageLibrary()
        guard library.canCreate else { throw FiestaBoardError.pageWritesDisabled }
        let fromSheet = name == nil
        let input = PageCreationInput(name: (name ?? library.name).trimmingCharacters(in: .whitespacesAndNewlines),
                                      family: family ?? (library.isPanel ? .panel(rows: library.rows, cols: library.columns) : .flagship),
                                      template: template)
        try input.validate()
        let token = generation
        library.phase = .working; library.deletion = nil
        var dispatched = false
        defer { if dispatched { pageLibraryEpoch &+= 1 } }
        do {
            let context = try await service.preparePageCreation(input)
            guard valid(token), pageLibrary === library else { throw FiestaBoardError.staleSession }
            library.blocked = true; pageLibraryEpoch &+= 1; dispatched = true
            let receipt = try await service.createPage(context: context)
            guard valid(token), pageLibrary === library else { throw FiestaBoardError.staleSession }
            if !pages.contains(where: { $0.id == receipt.page.id }) { pages.append(receipt.page) }
            if fromSheet { library.name = "" }
            library.blocked = false
            library.phase = .completed(fromSheet ? "Page created. Open its editor to add content." : "Saved “\(input.name)” as a page.")
            return receipt.page.id
        } catch {
            finishPageLibraryFailure(error, library: library, dispatched: dispatched)
            if token == generation { _ = handleAuthenticationLoss(error) }
            throw error
        }
    }

    public func preparePageDeletion(id: String) async throws {
        let (service, library) = try requirePageLibrary()
        guard library.canDelete, let page = pages.first(where: { $0.id == id }) else { throw FiestaBoardError.pageWritesDisabled }
        let identity = PageIdentity(deployment: service.deployment, id: id)
        guard !savingPages.contains(identity), !pageReadbacks.contains(identity) else { throw FiestaBoardError.pageReadbackRequired }
        guard pageDeletionDisabledReason(for: page) == nil else { throw FiestaBoardError.pageWritesDisabled }
        let token = generation; let writeEpoch = pageWriteGenerations[identity, default: 0]
        library.phase = .working; library.deletion = nil
        do {
            let context = try await service.readPageForDeletion(id: id)
            guard valid(token), pageLibrary === library else { throw FiestaBoardError.staleSession }
            guard !savingPages.contains(identity), writeEpoch == pageWriteGenerations[identity, default: 0] else { throw FiestaBoardError.stalePageContext }
            library.deletion = context; library.deletionGeneration = token; library.deletionWriteGeneration = writeEpoch
            library.phase = .idle
        } catch {
            library.phase = .failed(safeDescription(error))
            if token == generation { _ = handleAuthenticationLoss(error) }
            throw error
        }
    }

    public func cancelPageDeletion() { pageLibrary?.deletion = nil }

    public func deleteLibraryPage() async throws {
        let (service, library) = try requirePageLibrary()
        guard library.canDelete, let context = library.deletion,
              library.deletionGeneration == generation else { throw FiestaBoardError.stalePageContext }
        let identity = PageIdentity(deployment: service.deployment, id: context.page.id)
        guard !savingPages.contains(identity), !pageReadbacks.contains(identity),
              library.deletionWriteGeneration == pageWriteGenerations[identity, default: 0] else { throw FiestaBoardError.stalePageContext }
        let token = generation
        library.deletion = nil; library.phase = .working; library.blocked = true
        pageWriteGenerations[identity, default: 0] &+= 1; pageLibraryEpoch &+= 1
        savingPages.insert(identity); pageReadbacks.insert(identity); pageContexts.removeValue(forKey: context.page.id)
        library.deletionRecoveryEpochs[identity.id] = pageWriteGenerations[identity, default: 0]
        defer { savingPages.remove(identity); pageLibraryEpoch &+= 1 }
        var acknowledged = false
        do {
            let receipt = try await service.deletePage(context: context)
            acknowledged = true
            guard valid(token), pageLibrary === library else { throw FiestaBoardError.staleSession }
            pages.removeAll { $0.id == receipt.id }
            let summary = receipt.defaultPageCreated ? "Page deleted. The server created a replacement page." : "Page deleted."
            try await reloadPageLibraryState(service: service, library: library, token: token)
            pageReadbacks.remove(identity); library.deletionRecoveryEpochs.removeValue(forKey: identity.id); library.blocked = false
            library.phase = .completed(summary + " Library and display selections refreshed.")
        } catch {
            if acknowledged {
                library.phase = .reviewRequired("The server acknowledged deletion, but current library or display state could not be read. Review current state before another change.")
            } else {
                finishPageLibraryFailure(error, library: library, dispatched: true)
                if !library.blocked { pageReadbacks.remove(identity); library.deletionRecoveryEpochs.removeValue(forKey: identity.id) }
            }
            if token == generation { _ = handleAuthenticationLoss(error) }
            throw error
        }
    }

    private func finishPageLibraryFailure(_ error: any Error, library: PageLibraryState, dispatched: Bool) {
        let requiresReview: Bool
        switch error as? FiestaBoardError {
        case .unknownMutationOutcome, .staleSession, .stalePageContext, .pageConflict: requiresReview = dispatched
        case .none: requiresReview = dispatched
        default: requiresReview = false
        }
        library.blocked = requiresReview
        library.phase = requiresReview
            ? .reviewRequired("The result needs review. Your input is kept. Read the current library and display selections before starting another request; this request will not be repeated.")
            : .failed(safeDescription(error))
    }

    private func reloadPageLibraryState(service: any FiestaBoardService, library: PageLibraryState, token: UInt64) async throws {
        let epoch = pageLibraryEpoch
        let currentPages = try await service.pages()
        let summaries = try await service.boards()
        var details: [BoardDetail] = []
        for summary in summaries {
            let target = try BoardTarget(deployment: service.deployment, boardID: summary.id)
            details.append(try await service.board(target))
        }
        guard valid(token), pageLibrary === library else { throw FiestaBoardError.staleSession }
        guard epoch == pageLibraryEpoch else { throw FiestaBoardError.stalePageContext }
        pages = currentPages; boards = summaries
        if let selectedBoardID { board = details.first { $0.summary.id == selectedBoardID } }
        defaultPageContext = nil
        if let target { await loadDefaultContext(service, target: target, token: token) }
        guard valid(token), pageLibrary === library else { throw FiestaBoardError.staleSession }
    }

    public func reviewPageLibrary() async {
        guard let service, let library = pageLibrary, !library.busy, !connecting, status != nil else { return }
        let token = generation
        library.phase = .working
        do {
            try await reloadPageLibraryState(service: service, library: library, token: token)
            library.phase = library.blocked
                ? .reviewed("Current pages and display selections are loaded. A matching page name or missing page does not prove the earlier request succeeded. Inspect the library before starting a new request.")
                : .completed("Library and display selections refreshed.")
        } catch {
            library.phase = library.blocked ? .reviewRequired(safeDescription(error)) : .failed(safeDescription(error))
            if token == generation { _ = handleAuthenticationLoss(error) }
        }
    }

    public func acknowledgePageLibraryReview() {
        guard let library = pageLibrary, case .reviewed = library.phase else { return }
        for (id, epoch) in library.deletionRecoveryEpochs {
            let identity = PageIdentity(deployment: library.deployment, id: id)
            if pageWriteGenerations[identity, default: 0] == epoch && !savingPages.contains(identity) {
                pageReadbacks.remove(identity)
            }
        }
        library.deletionRecoveryEpochs.removeAll()
        library.blocked = false; library.deletion = nil; library.phase = .idle
    }
}


@MainActor extension BoardStore {
    private func clearSchedules() {
        scheduleTask?.cancel(); scheduleTask = nil; scheduleRequest = UUID()
        scheduleList = nil; scheduleTarget = nil; scheduleMessage = nil; schedulesLoading = false
    }
    /// One read bound to this selected display, session generation and request.
    @discardableResult public func refreshSchedules() -> Task<Void, Never> {
        clearSchedules()
        guard let service, status != nil, !connecting else {
            scheduleMessage = ActionDisabledReason.disconnected.message
            return Task {}
        }
        guard let target else {
            scheduleMessage = ActionDisabledReason.noDisplay.message
            return Task {}
        }
        let session = generation, request = UUID()
        scheduleRequest = request; schedulesLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if scheduleRequest == request { schedulesLoading = false } }
            do {
                let value = try await service.schedules(on: target)
                guard valid(session), scheduleRequest == request, self.target == target else { return }
                scheduleTarget = target; scheduleList = value
            } catch {
                guard valid(session), scheduleRequest == request, self.target == target else { return }
                if !handleAuthenticationLoss(error) {
                    switch error as? FiestaBoardError {
                    case .rejected(status: 404), .unsupportedOperation:
                        scheduleMessage = "Schedule reading is unavailable for this display or server. No schedule changes are supported here."
                    default: scheduleMessage = safeDescription(error)
                    }
                }
            }
        }
        scheduleTask = task
        return task
    }
}
