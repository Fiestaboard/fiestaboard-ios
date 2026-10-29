import Foundation

public protocol FiestaBoardService: Sendable {
    var deployment: DeploymentURL { get }
    var isDemo: Bool { get }
    func bootstrap() async throws -> BootstrapSnapshot
    func setAuthenticationPreference(enabled: Bool, setupToken: String?) async throws -> AuthStatus
    func setupAdministrator(username: String, password: String, setupToken: String?) async throws -> AuthStatus
    func login(username: String, password: String, rememberMe: Bool) async throws -> AuthStatus
    func authStatus() async throws -> AuthStatus
    func login(username: String, password: String) async throws -> AuthStatus
    func configureSessionPersistence(rememberMe: Bool, installationID: String?) async
    func restoreRememberedSession(observedInstallationID: String) async throws -> Bool
    func forgetRememberedSession() async
    func disconnect() async
    func sessionPersistenceState() async -> SessionPersistenceState
    func logout() async throws
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus
    func boards() async throws -> [BoardSummary]
    func board(_ target: BoardTarget) async throws -> BoardDetail
    func collectionAccess() async -> CollectionWriteAccess
    func collections() async throws -> [PageCollection]
    func collection(id: String) async throws -> PageCollection
    func acknowledgeCollectionCreationReview() async throws
    func createCollection(_ input: CollectionInput) async throws -> PageCollection
    func updateCollection(id: String, input: CollectionInput, expectedRevision: String) async throws -> PageCollection
    func deleteCollection(id: String, expectedRevision: String) async throws
    func pages() async throws -> [Page]
    func pageDocumentData(id: String) async throws -> Data
    func page(id: String) async throws -> Page
    func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt
    func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult
    func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult
    func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt
    func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult
}

/// A bounded v10 candidate adapter. No released server pairing is claimed supported.
public actor LiveFiestaBoardService: FiestaBoardService {
    public nonisolated let deployment: DeploymentURL
    public nonisolated let isDemo = false
    private let transport: any APITransport
    private let allowsSimulatedCollectionWrites: Bool
    private var generation: UInt64 = 0
    private var observedInstallationID: String?
    private var persistenceWarning: SessionPersistenceWarning?
    private var access = DraftAccess.readOnly
    private var pageWritesOptedIn = false
    private var previewAudited = false
    private var knownPages: [String: Page] = [:]
    private var savingPages: Set<String> = []
    private var pageReadbacks: Set<String> = []
    private var pageWriteGenerations: [String: UInt64] = [:]
    private var collectionWritesOptedIn = false
    private var collectionCreateAudited = false
    private var collectionOriginalRevisions: [String: Set<String>] = [:]
    private var savingCollections: Set<String> = []
    private var collectionReadbacks: Set<String> = []
    private var collectionWriteGenerations: [String: UInt64] = [:]
    private var collectionCreationWriteGeneration: UInt64 = 0
    private var collectionCreationReviewed = false
    private var creatingCollection = false
    private var collectionCreateReadbackRequired = false
    private var knownBoards: [String: BoardSummary] = [:]

    public init(deployment: DeploymentURL, transport: (any APITransport)? = nil, vault: (any SessionVault)? = nil) {
        self.deployment = deployment
        self.transport = transport ?? URLSessionTransport(deployment: deployment, vault: vault)
        allowsSimulatedCollectionWrites = false
    }

    /// The Demo wrapper supplies an in-memory transport; this never changes board-control gates.
    init(demoDeployment: DeploymentURL, transport: any APITransport) {
        deployment = demoDeployment
        self.transport = transport
        allowsSimulatedCollectionWrites = true
    }

    public func bootstrap() async throws -> BootstrapSnapshot {
        try await bootstrapSnapshot(invalidateUnauthenticated: true)
    }

    private func bootstrapSnapshot(invalidateUnauthenticated: Bool) async throws -> BootstrapSnapshot {
        let token = generation
        try Task.checkCancellation()
        let health: ServerHealth = try await fetch(APIRequest(path: ["health"], cachePolicy: .noStore))
        guard token == generation else { throw FiestaBoardError.staleSession }
        try Task.checkCancellation()
        let identity: ServerIdentity = try await fetch(APIRequest(path: ["discover"], cachePolicy: .noStore))
        guard identity.product == "FiestaBoard" else { throw FiestaBoardError.wrongProduct }
        guard token == generation else { throw FiestaBoardError.staleSession }
        observedInstallationID = identity.installationID
        let auth: AuthStatus = try await fetch(APIRequest(path: ["auth", "status"], cachePolicy: .noStore), invalidateUnauthenticated: invalidateUnauthenticated)
        guard token == generation else { throw FiestaBoardError.staleSession }
        try Task.checkCancellation()
        if invalidateUnauthenticated && auth.enabled && !auth.authenticated { invalidateAuthentication() }
        return BootstrapSnapshot(deployment: deployment, health: health, identity: identity, auth: auth)
    }

    public func setAuthenticationPreference(enabled: Bool, setupToken: String? = nil) async throws -> AuthStatus {
        guard enabled || setupToken == nil else { throw FiestaBoardError.invalidRequestContext }
        struct Body: Encodable { let enabled: Bool }
        let token = try await beginAuthenticationTransition()
        try await onboardingAcknowledgement(APIRequest(.post, path: ["auth", "preference"],
            body: JSONEncoder().encode(Body(enabled: enabled)), context: setupToken.map(APIRequestContext.onboardingToken) ?? .standard, cachePolicy: .noStore), expectedStatus: 200)
        guard token == generation else { throw FiestaBoardError.staleSession }
        let status = try await verifiedAuthReadback()
        guard status.enabled == enabled, status.mode == (enabled ? "enabled" : "disabled"), status.firstRun != true else { throw FiestaBoardError.unknownMutationOutcome }
        return status
    }

    public func setupAdministrator(username: String, password: String, setupToken: String? = nil) async throws -> AuthStatus {
        struct Body: Encodable { let username: String; let password: String }
        let token = try await beginAuthenticationTransition()
        try await onboardingAcknowledgement(APIRequest(.post, path: ["auth", "setup"],
            body: JSONEncoder().encode(Body(username: username, password: password)), context: setupToken.map(APIRequestContext.onboardingToken) ?? .standard, cachePolicy: .noStore), expectedStatus: 201)
        guard token == generation else { throw FiestaBoardError.staleSession }
        let status = try await verifiedAuthReadback()
        guard status.enabled, status.bootstrapPhase == .ready, status.authenticated, status.username == username else { throw FiestaBoardError.unknownMutationOutcome }
        return status
    }

    private func onboardingAcknowledgement(_ request: APIRequest, expectedStatus: Int) async throws {
        struct Reply: Decodable { let status: String }
        let value = try await response(request)
        guard value.status == expectedStatus, (try? JSONDecoder().decode(Reply.self, from: value.data).status) == "ok" else { throw FiestaBoardError.unknownMutationOutcome }
    }

    private func verifiedAuthReadback() async throws -> AuthStatus {
        do { return try await authStatus() }
        catch FiestaBoardError.staleSession { throw FiestaBoardError.staleSession }
        catch { throw FiestaBoardError.unknownMutationOutcome }
    }

    public func authStatus() async throws -> AuthStatus {
        let status: AuthStatus = try await fetch(APIRequest(path: ["auth", "status"], cachePolicy: .noStore))
        if status.enabled && !status.authenticated { invalidateAuthentication() }
        return status
    }

    public func login(username: String, password: String) async throws -> AuthStatus {
        try await login(username: username, password: password, rememberMe: false)
    }

    /// Retire old reads/mutations before dispatch and clear their cookie generation before accepting a replacement session.
    private func beginAuthenticationTransition() async throws -> UInt64 {
        generation &+= 1
        resetCollectionSession()
        access = .readOnly
        pageWritesOptedIn = false; previewAudited = false; knownPages = [:]
        knownBoards = [:]
        let token = generation
        await transport.resetSession()
        guard token == generation else { throw FiestaBoardError.staleSession }
        return token
    }

    public func login(username: String, password: String, rememberMe: Bool) async throws -> AuthStatus {
        let token = try await beginAuthenticationTransition()
        await transport.configureSessionPersistence(rememberMe: rememberMe, installationID: observedInstallationID)
        guard token == generation else { throw FiestaBoardError.staleSession }
        struct Login: Encodable { let username: String; let password: String; let remember_me: Bool }
        struct Reply: Decodable { let status: String }
        let reply: Reply = try await fetch(APIRequest(.post, path: ["auth", "login"],
                              body: JSONEncoder().encode(Login(username: username, password: password, remember_me: rememberMe)), cachePolicy: .noStore))
        guard reply.status == "ok" else { throw FiestaBoardError.unknownMutationOutcome }
        guard token == generation else { throw FiestaBoardError.staleSession }
        let status = try await verifiedAuthReadback()
        guard status.authenticated, status.bootstrapPhase == .ready, status.username == username else { throw FiestaBoardError.unknownMutationOutcome }
        return status
    }

    public func configureSessionPersistence(rememberMe: Bool, installationID: String?) async {
        // The service only trusts an identity observed through its own fresh bootstrap.
        let identity = installationID == observedInstallationID ? observedInstallationID : nil
        await transport.configureSessionPersistence(rememberMe: rememberMe, installationID: identity)
    }

    public func sessionPersistenceState() async -> SessionPersistenceState {
        var state = await transport.sessionPersistenceState()
        if let persistenceWarning { state.warning = persistenceWarning }
        return state
    }

    /// Fresh public discovery precedes import; fresh authenticated bootstrap follows it.
    /// Imported material never grants write access or reuses an old document generation.
    public func restoreRememberedSession(observedInstallationID: String) async throws -> Bool {
        let token = try await beginAuthenticationTransition()
        let publicSnapshot = try await bootstrapSnapshot(invalidateUnauthenticated: false)
        guard token == generation else { throw FiestaBoardError.staleSession }
        guard !observedInstallationID.isEmpty, publicSnapshot.identity.installationID == observedInstallationID else { return false }
        guard await transport.restoreRememberedSession(observedInstallationID: observedInstallationID) else { return false }
        guard token == generation else { throw FiestaBoardError.staleSession }
        do {
            let verified = try await bootstrapSnapshot(invalidateUnauthenticated: false)
            guard token == generation else { throw FiestaBoardError.staleSession }
            guard verified.identity.installationID == observedInstallationID, verified.auth.authenticated,
                  verified.auth.bootstrapPhase == .ready else {
                await transport.forgetRememberedSession(); await transport.resetSession(); return false
            }
            return true
        } catch {
            guard token == generation else { throw FiestaBoardError.staleSession }
            if (error as? FiestaBoardError) == .unauthenticated {
                await transport.forgetRememberedSession()
                guard token == generation else { throw FiestaBoardError.staleSession }
                await transport.resetSession()
                return false
            }
            await transport.resetSession()
            throw error
        }
    }

    public func forgetRememberedSession() async { await transport.forgetRememberedSession() }

    /// Local disconnect clears active cookies and capability/document generations.
    /// Explicit remembered material remains available for a future revalidated restore.
    public func disconnect() async {
        _ = try? await beginAuthenticationTransition()
    }

    public func logout() async throws {
        generation &+= 1
        resetCollectionSession()
        let token = generation
        access = .readOnly
        pageWritesOptedIn = false; previewAudited = false; knownPages = [:]
        knownBoards = [:]
        persistenceWarning = nil
        await transport.forgetRememberedSession()
        guard generation == token else { throw FiestaBoardError.staleSession }
        do {
            struct Reply: Decodable { let status: String }
            let _: Reply = try await fetch(APIRequest(.post, path: ["auth", "logout"]))
            if generation == token { await transport.resetSession() }
        } catch {
            if generation == token {
                await transport.resetSession()
                persistenceWarning = .remoteRevocationPending
            }
            throw error
        }
    }

    public func connect(allowCandidateWrites: Bool = false) async throws -> ConnectionStatus {
        generation &+= 1
        resetCollectionSession()
        let token = generation
        access = .readOnly
        pageWritesOptedIn = false; previewAudited = false; knownPages = [:]
        knownBoards = [:]
        let version: VersionInfo = try await fetch(APIRequest(path: ["version"]))
        let boards = try await boards()
        guard generation == token else { throw FiestaBoardError.staleSession }
        knownBoards = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0) })
        collectionWritesOptedIn = allowCandidateWrites
        collectionCreateAudited = allowsSimulatedCollectionWrites || (version.runningVersion == "10.1.7" && !version.isDev)
        pageWritesOptedIn = allowCandidateWrites
        previewAudited = ["10.0.0", "10.1.2", "10.1.7"].contains(version.runningVersion ?? "") && !version.isDev
        if allowCandidateWrites && version.runningVersion == "10.0.0" && !version.isDev { access = .candidateWrites }
        return ConnectionStatus(version: version, access: access, isDemo: false, sessionPersistence: "Memory only")
    }

    public func boards() async throws -> [BoardSummary] {
        struct List: Decodable { let boards: [BoardSummary]; let total: Int }
        let list: List = try await fetch(APIRequest(path: ["v1", "boards"]))
        guard list.total == list.boards.count, Set(list.boards.map(\.id)).count == list.boards.count else {
            throw FiestaBoardError.invalidResponse
        }
        try list.boards.forEach { try $0.validate() }
        return list.boards
    }

    public func board(_ target: BoardTarget) async throws -> BoardDetail {
        try validateTarget(target)
        let detail: BoardDetail = try await fetch(APIRequest(path: ["v1", "boards", target.boardID]))
        try detail.validate()
        guard detail.summary.id == target.boardID else { throw FiestaBoardError.invalidResponse }
        return detail
    }

    public func pages() async throws -> [Page] {
        struct List: Decodable { let pages: [Page]; let total: Int }
        let list: List = try await fetch(APIRequest(path: ["v1", "pages"]))
        guard list.total == list.pages.count, Set(list.pages.map(\.id)).count == list.pages.count else {
            throw FiestaBoardError.invalidResponse
        }
        return list.pages
    }

    public func page(id: String) async throws -> Page {
        guard DeploymentURL.validSegment(id) else { throw FiestaBoardError.invalidPath }
        let writeGeneration = pageWriteGenerations[id, default: 0]
        let page: Page = try await fetch(APIRequest(path: ["v1", "pages", id]))
        guard writeGeneration == pageWriteGenerations[id, default: 0] else { throw FiestaBoardError.stalePageContext }
        guard page.id == id else { throw FiestaBoardError.invalidResponse }
        knownPages[id] = page
        if !savingPages.contains(id) { pageReadbacks.remove(id) }
        return page
    }

    /// Returns the exact public document bytes, preserving fields outside the read-only Page projection.
    public func pageDocumentData(id: String) async throws -> Data {
        guard DeploymentURL.validSegment(id) else { throw FiestaBoardError.invalidPath }
        let writeGeneration = pageWriteGenerations[id, default: 0]
        let result = try await response(APIRequest(path: ["v1", "pages", id]))
        guard writeGeneration == pageWriteGenerations[id, default: 0] else { throw FiestaBoardError.stalePageContext }
        guard let page = try? JSONDecoder().decode(Page.self, from: result.data), page.id == id else {
            throw FiestaBoardError.invalidResponse
        }
        knownPages[id] = page
        if !savingPages.contains(id) { pageReadbacks.remove(id) }
        return result.data
    }

    public func savePage(id: String, patch: PageSavePatch) async throws -> PageSaveReceipt {
        guard DeploymentURL.validSegment(id) else { throw FiestaBoardError.invalidPath }
        try patch.validate()
        guard pageWritesOptedIn, let baseline = knownPages[id], baseline.editProtocol == "page-revision-v1",
              baseline.revision?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, baseline.type == "template" else { throw FiestaBoardError.pageWritesDisabled }
        guard !savingPages.contains(id), !pageReadbacks.contains(id) else { throw FiestaBoardError.pageReadbackRequired }
        pageWriteGenerations[id, default: 0] &+= 1
        savingPages.insert(id); pageReadbacks.insert(id)
        defer { savingPages.remove(id) }
        do {
            let response = try await response(APIRequest(.put, path: ["v1", "pages", id], body: JSONEncoder().encode(patch)))
            if response.status == 412 { throw FiestaBoardError.pageConflict }
            guard response.status == 200 else { throw FiestaBoardError.unknownMutationOutcome }
            let receipt = try PageSaveReceipt(rawData: response.data, expectedPageID: id)
            let updated = try JSONDecoder().decode(Page.self, from: receipt.pageData)
            guard updated.revision != patch.expectedRevision else { throw FiestaBoardError.unknownMutationOutcome }
            knownPages[id] = updated; pageReadbacks.remove(id)
            return receipt
        } catch {
            switch error as? FiestaBoardError {
            case .unknownMutationOutcome, .pageConflict, .staleSession, .stalePageContext: break
            default: pageReadbacks.remove(id)
            }
            throw error
        }
    }
    public func validatePage(requestData: Data, target: BoardTarget) async throws -> TemplateValidationResult {
        try requirePreview(requestData, target: target, render: false)
        let result = try await response(APIRequest(.post, path: ["templates", "validate"], body: requestData))
        return try TemplateValidationResult(rawData: result.data)
    }
    public func previewPage(requestData: Data, target: BoardTarget) async throws -> TemplatePreviewResult {
        try requirePreview(requestData, target: target, render: true)
        let result = try await response(APIRequest(.post, path: ["templates", "render"], body: requestData))
        return try TemplatePreviewResult(rawData: result.data)
    }
    private func requirePreview(_ data: Data, target: BoardTarget, render: Bool) throws {
        try validateTarget(target)
        guard previewAudited else { throw FiestaBoardError.previewUnsupported }
        guard knownBoards[target.boardID] != nil,
              let members = try? RawJSONObject.members(data), let boardData = members["board_id"],
              (try? JSONDecoder().decode(String.self, from: boardData)) == target.boardID,
              let template = members["template"],
              (try? JSONDecoder().decode(String.self, from: template)) != nil || (try? JSONDecoder().decode([String].self, from: template)) != nil else { throw FiestaBoardError.invalidTarget }
        let allowed: Set<String> = render
            ? ["template", "board_id", "device_type", "notes_wide", "notes_tall", "grid_rows", "grid_cols", "line_metadata", "canvases"]
            : ["template", "board_id"]
        guard Set(members.keys).isSubset(of: allowed) else { throw FiestaBoardError.previewUnsupported }
    }

    public func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult {
        try requireWrites(target)
        struct Body: Encodable { let text: String }
        struct Reply: Decodable {
            let sent: Bool; let board_id: String; let characters: [[Int]]; let text: String
            let silenced: Bool?; let held: Bool?
        }
        let response = try await response(APIRequest(.post, path: ["v1", "boards", target.boardID, "message"],
                                   body: JSONEncoder().encode(Body(text: text))))
        guard let reply = try? JSONDecoder().decode(Reply.self, from: response.data), reply.board_id == target.boardID,
              let geometry = knownBoards[target.boardID], reply.characters.count == geometry.rows,
              reply.characters.allSatisfy({ $0.count == geometry.cols }),
              !(reply.sent && (reply.held == true || response.status == 202)) else {
            throw FiestaBoardError.unknownMutationOutcome
        }
        return MutationResult(boardID: reply.board_id, pageID: nil,
            disposition: (reply.held == true || response.status == 202) ? .held : (reply.sent ? .accepted : .notSent),
            sent: reply.sent, silenced: reply.silenced ?? false, deliveryFailed: false, warningCount: 0)
    }

    public func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult {
        try requireWrites(target)
        guard DeploymentURL.validSegment(id) else { throw FiestaBoardError.invalidPath }
        struct Body: Encodable { let page_id: String }
        struct Reply: Decodable {
            let board_id: String; let page_id: String?; let sent: Bool
            let silenced: Bool?; let error: String?; let warnings: [String]?
        }
        let reply: Reply = try await fetch(APIRequest(.put, path: ["v1", "boards", target.boardID, "active-page"],
                                       body: JSONEncoder().encode(Body(page_id: id))))
        guard reply.board_id == target.boardID, reply.page_id == id else { throw FiestaBoardError.unknownMutationOutcome }
        return MutationResult(boardID: target.boardID, pageID: reply.page_id,
            disposition: reply.sent ? .accepted : .selectionStored, sent: reply.sent,
            silenced: reply.silenced ?? false, deliveryFailed: reply.error != nil, warningCount: reply.warnings?.count ?? 0)
    }

    public func updateBoard(_ patch: BoardPatch, on target: BoardTarget) async throws -> BoardConfigurationReceipt {
        try requireWrites(target)
        try patch.validate()
        let detail: BoardDetail = try await fetch(APIRequest(.patch, path: ["v1", "boards", target.boardID],
                                                            body: JSONEncoder().encode(patch)))
        do { try detail.validate() } catch { throw FiestaBoardError.unknownMutationOutcome }
        guard detail.summary.id == target.boardID else { throw FiestaBoardError.unknownMutationOutcome }
        return BoardConfigurationReceipt(board: detail)
    }

    public func restoreBoard(_ target: BoardTarget) async throws -> BoardRestoreReceipt {
        try requireWrites(target)
        // The pinned send executor can wait behind a 120-second transition, then run another.
        let receipt: BoardRestoreReceipt = try await fetch(APIRequest(.post, path: ["v1", "boards", target.boardID, "restore"], timeout: 300))
        guard receipt.boardID == target.boardID, !receipt.deviceObserved,
              receipt.pageID.map(DeploymentURL.validSegment) ?? true else { throw FiestaBoardError.unknownMutationOutcome }
        return receipt
    }

    private func validateTarget(_ target: BoardTarget) throws {
        guard target.deployment == deployment else { throw FiestaBoardError.invalidTarget }
    }
    private func requireWrites(_ target: BoardTarget) throws {
        try validateTarget(target)
        guard access == .candidateWrites else { throw FiestaBoardError.writesDisabled }
        guard knownBoards[target.boardID] != nil else { throw FiestaBoardError.invalidTarget }
    }
    private func response(_ request: APIRequest, invalidateUnauthenticated: Bool = true) async throws -> APIResponse {
        let token = generation
        do {
            let result = try await transport.send(request)
            guard token == generation else { throw FiestaBoardError.staleSession }
            return result
        } catch {
            guard token == generation else { throw FiestaBoardError.staleSession }
            if invalidateUnauthenticated && (error as? FiestaBoardError) == .unauthenticated { invalidateAuthentication() }
            if error is CancellationError && !request.isMutation { throw error }
            throw (error as? FiestaBoardError) ?? (request.isMutation ? .unknownMutationOutcome : .networkUnavailable)
        }
    }
    private func fetch<T: Decodable & Sendable>(_ request: APIRequest, invalidateUnauthenticated: Bool = true) async throws -> T {
        let response = try await response(request, invalidateUnauthenticated: invalidateUnauthenticated)
        do { return try JSONDecoder().decode(T.self, from: response.data) }
        catch let error as FiestaBoardError where !request.isMutation { throw error }
        catch { throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .invalidResponse }
    }
}


extension LiveFiestaBoardService {
    private func resetCollectionSession() {
        collectionWritesOptedIn = false; collectionCreateAudited = false
        collectionOriginalRevisions = [:]; savingCollections = []; collectionReadbacks = []
        collectionWriteGenerations = [:]; creatingCollection = false; collectionCreateReadbackRequired = false
        collectionCreationWriteGeneration = 0; collectionCreationReviewed = false
    }
    private func invalidateAuthentication() {
        generation &+= 1
        access = .readOnly; pageWritesOptedIn = false; knownPages = [:]
        resetCollectionSession()
    }
    public func collectionAccess() async -> CollectionWriteAccess {
        .init(writesOptedIn: collectionWritesOptedIn,
              canCreate: collectionWritesOptedIn && collectionCreateAudited && !creatingCollection && !collectionCreateReadbackRequired,
              isSimulated: false)
    }
    public func collections() async throws -> [PageCollection] {
        struct List: Decodable { let collections: [PageCollection]; let total: Int }
        let creationGeneration = collectionCreationWriteGeneration
        let startedDuringCreate = creatingCollection
        let result = try await collectionResponse(APIRequest(path: ["v1", "collections"]))
        guard result.status == 200, let list = try? JSONDecoder().decode(List.self, from: result.data),
              list.total == list.collections.count, Set(list.collections.map(\.id)).count == list.collections.count,
              list.collections.allSatisfy({ Self.validCollectionID($0.id) }) else { throw FiestaBoardError.invalidResponse }
        // List review alone never unlocks creation. Only explicit acknowledgement may do so.
        if collectionCreateReadbackRequired, !startedDuringCreate, !creatingCollection,
           creationGeneration == collectionCreationWriteGeneration { collectionCreationReviewed = true }
        return list.collections
    }
    public func collection(id: String) async throws -> PageCollection {
        guard Self.validCollectionID(id) else { throw FiestaBoardError.invalidPath }
        let writeGeneration = collectionWriteGenerations[id, default: 0]
        let startedDuringWrite = savingCollections.contains(id)
        let result = try await collectionResponse(APIRequest(path: ["v1", "collections", id]))
        guard !startedDuringWrite, writeGeneration == collectionWriteGenerations[id, default: 0], !savingCollections.contains(id) else {
            throw FiestaBoardError.staleCollectionContext
        }
        guard result.status == 200, (try? RawJSONObject.members(result.data)) != nil,
              let value = try? JSONDecoder().decode(PageCollection.self, from: result.data), value.id == id else {
            throw FiestaBoardError.invalidResponse
        }
        authorizeCollection(value)
        collectionReadbacks.remove(id)
        return value
    }
    /// Allows a new draft after explicit review. It does not authorize replay of the old draft.
    public func acknowledgeCollectionCreationReview() async throws {
        guard collectionWritesOptedIn, collectionCreateAudited else { throw FiestaBoardError.collectionWritesDisabled }
        guard !creatingCollection else { throw FiestaBoardError.collectionReadbackRequired }
        // A reconnect clears the SDK barrier while the Store retains its consumed draft context.
        // Explicit review is then already acknowledged locally; do not block a new Store draft.
        guard collectionCreateReadbackRequired else { return }
        guard collectionCreationReviewed else { throw FiestaBoardError.collectionReadbackRequired }
        collectionCreateReadbackRequired = false; collectionCreationReviewed = false
    }
    public func createCollection(_ input: CollectionInput) async throws -> PageCollection {
        try input.validate()
        guard collectionWritesOptedIn, collectionCreateAudited else { throw FiestaBoardError.collectionWritesDisabled }
        guard !creatingCollection, !collectionCreateReadbackRequired else { throw FiestaBoardError.collectionReadbackRequired }
        let token = generation
        creatingCollection = true; collectionCreateReadbackRequired = true; collectionCreationReviewed = false
        collectionCreationWriteGeneration &+= 1
        defer {
            if generation == token { creatingCollection = false; collectionCreationWriteGeneration &+= 1 }
        }
        do {
            let result = try await collectionResponse(APIRequest(.post, path: ["v1", "collections"], body: JSONEncoder().encode(input)))
            let value = try collectionReceipt(result, expectedStatus: 201, expectedID: nil, expectedRevision: nil)
            authorizeCollection(value); collectionCreateReadbackRequired = false
            return value
        } catch {
            if generation == token, !Self.requiresCollectionReadback(error) { collectionCreateReadbackRequired = false }
            throw error
        }
    }
    public func updateCollection(id: String, input: CollectionInput, expectedRevision: String) async throws -> PageCollection {
        try input.validate()
        try requireCollectionWrite(id: id, expectedRevision: expectedRevision)
        let token = generation
        beginCollectionWrite(id)
        defer { if generation == token { finishCollectionWrite(id) } }
        do {
            struct Update: Encodable {
                let input: CollectionInput; let expectedRevision: String
                enum CodingKeys: String, CodingKey { case expectedRevision = "expected_revision" }
                func encode(to encoder: any Encoder) throws {
                    try input.encode(to: encoder)
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encode(expectedRevision, forKey: .expectedRevision)
                }
            }
            let body = try JSONEncoder().encode(Update(input: input, expectedRevision: expectedRevision))
            let result = try await collectionResponse(APIRequest(.put, path: ["v1", "collections", id], body: body))
            let value = try collectionReceipt(result, expectedStatus: 200, expectedID: id, expectedRevision: expectedRevision)
            authorizeCollection(value); collectionReadbacks.remove(id)
            return value
        } catch {
            if generation == token, !Self.requiresCollectionReadback(error) { collectionReadbacks.remove(id) }
            throw error
        }
    }
    public func deleteCollection(id: String, expectedRevision: String) async throws {
        try requireCollectionWrite(id: id, expectedRevision: expectedRevision)
        let token = generation
        beginCollectionWrite(id)
        defer { if generation == token { finishCollectionWrite(id) } }
        do {
            let result = try await collectionResponse(APIRequest(.delete, path: ["v1", "collections", id],
                queryItems: [.init(name: "expected_revision", value: expectedRevision)]))
            guard result.status == 200, let fields = try? RawJSONObject.members(result.data), let idData = fields["id"],
                  (try? JSONDecoder().decode(String.self, from: idData)) == id else { throw FiestaBoardError.unknownMutationOutcome }
            collectionOriginalRevisions.removeValue(forKey: id); collectionReadbacks.remove(id)
        } catch {
            if generation == token, !Self.requiresCollectionReadback(error) { collectionReadbacks.remove(id) }
            throw error
        }
    }
    private static func validCollectionID(_ id: String) -> Bool {
        id.hasPrefix("collection:") && DeploymentURL.validAPISegment(id)
    }
    private func authorizeCollection(_ value: PageCollection) {
        if value.supportsEditing, value.editProtocol == "collection-revision-v1", let revision = value.revision,
           !revision.isEmpty, revision.count <= 128 {
            collectionOriginalRevisions[value.id, default: []].insert(revision)
        }
    }
    private func requireCollectionWrite(id: String, expectedRevision: String) throws {
        guard Self.validCollectionID(id) else { throw FiestaBoardError.invalidPath }
        guard collectionWritesOptedIn, collectionOriginalRevisions[id]?.contains(expectedRevision) == true else {
            throw FiestaBoardError.collectionWritesDisabled
        }
        guard !savingCollections.contains(id), !collectionReadbacks.contains(id) else { throw FiestaBoardError.collectionReadbackRequired }
    }
    private func beginCollectionWrite(_ id: String) {
        collectionWriteGenerations[id, default: 0] &+= 1
        savingCollections.insert(id); collectionReadbacks.insert(id)
    }
    private func finishCollectionWrite(_ id: String) {
        collectionWriteGenerations[id, default: 0] &+= 1
        savingCollections.remove(id)
    }
    private static func requiresCollectionReadback(_ error: any Error) -> Bool {
        switch error as? FiestaBoardError {
        case .unknownMutationOutcome, .collectionConflict, .staleSession, .staleCollectionContext: return true
        default: return false
        }
    }
    private func collectionReceipt(_ result: APIResponse, expectedStatus: Int, expectedID: String?, expectedRevision: String?) throws -> PageCollection {
        guard result.status == expectedStatus, (try? RawJSONObject.members(result.data)) != nil,
              let value = try? JSONDecoder().decode(PageCollection.self, from: result.data),
              Self.validCollectionID(value.id), expectedID.map({ value.id == $0 }) ?? true,
              value.supportsEditing, value.editProtocol == "collection-revision-v1",
              let revision = value.revision, !revision.isEmpty, revision.count <= 128,
              expectedRevision.map({ revision != $0 }) ?? true else { throw FiestaBoardError.unknownMutationOutcome }
        return value
    }
    private func collectionResponse(_ request: APIRequest) async throws -> APIResponse {
        do {
            let value = try await response(request)
            if Task.isCancelled { throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .staleCollectionContext }
            switch value.status {
            case 200..<300: return value
            case 401: invalidateAuthentication(); throw FiestaBoardError.unauthenticated
            case 412: throw FiestaBoardError.collectionConflict
            case 409 where request.method == .delete: throw FiestaBoardError.collectionInUse
            case 409: throw FiestaBoardError.conflict
            case 500...599 where request.isMutation: throw FiestaBoardError.unknownMutationOutcome
            default: throw FiestaBoardError.rejected(status: value.status)
            }
        } catch FiestaBoardError.partialWrite where request.isMutation {
            // Collection storage has no board-region partial-write contract.
            throw FiestaBoardError.unknownMutationOutcome
        } catch FiestaBoardError.pageConflict { throw FiestaBoardError.collectionConflict }
        catch FiestaBoardError.conflict where request.method == .delete { throw FiestaBoardError.collectionInUse }
    }
}
