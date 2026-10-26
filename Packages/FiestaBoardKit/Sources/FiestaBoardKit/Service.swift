import Foundation

public protocol FiestaBoardService: Sendable {
    var deployment: DeploymentURL { get }
    var isDemo: Bool { get }
    func authStatus() async throws -> AuthStatus
    func login(username: String, password: String) async throws -> AuthStatus
    func logout() async throws
    func connect(allowCandidateWrites: Bool) async throws -> ConnectionStatus
    func boards() async throws -> [BoardSummary]
    func board(_ target: BoardTarget) async throws -> BoardDetail
    func pages() async throws -> [Page]
    func page(id: String) async throws -> Page
    func sendText(_ text: String, to target: BoardTarget) async throws -> MutationResult
    func selectPage(id: String, on target: BoardTarget) async throws -> MutationResult
}

/// A bounded v10 candidate adapter. No released server pairing is claimed supported.
public actor LiveFiestaBoardService: FiestaBoardService {
    public nonisolated let deployment: DeploymentURL
    public nonisolated let isDemo = false
    private let transport: any APITransport
    private var generation: UInt64 = 0
    private var access = DraftAccess.readOnly
    private var knownBoards: [String: BoardSummary] = [:]

    public init(deployment: DeploymentURL, transport: (any APITransport)? = nil) {
        self.deployment = deployment
        self.transport = transport ?? URLSessionTransport(deployment: deployment)
    }

    public func authStatus() async throws -> AuthStatus {
        let status: AuthStatus = try await fetch(APIRequest(path: ["auth", "status"]))
        if status.enabled && !status.authenticated { access = .readOnly }
        return status
    }

    public func login(username: String, password: String) async throws -> AuthStatus {
        generation &+= 1
        access = .readOnly
        knownBoards = [:]
        let token = generation
        await transport.resetSession()
        guard token == generation else { throw FiestaBoardError.staleSession }
        struct Login: Encodable { let username: String; let password: String; let remember_me = false }
        struct Reply: Decodable { let status: String }
        let reply: Reply = try await fetch(APIRequest(.post, path: ["auth", "login"],
                              body: JSONEncoder().encode(Login(username: username, password: password))))
        guard reply.status == "ok" else { throw FiestaBoardError.invalidResponse }
        return try await authStatus()
    }

    public func logout() async throws {
        generation &+= 1
        let token = generation
        access = .readOnly
        knownBoards = [:]
        do {
            struct Reply: Decodable { let status: String }
            let _: Reply = try await fetch(APIRequest(.post, path: ["auth", "logout"]))
            if generation == token { await transport.resetSession() }
        } catch {
            if generation == token { await transport.resetSession() }
            throw error
        }
    }

    public func connect(allowCandidateWrites: Bool = false) async throws -> ConnectionStatus {
        generation &+= 1
        let token = generation
        access = .readOnly
        knownBoards = [:]
        let version: VersionInfo = try await fetch(APIRequest(path: ["version"]))
        let boards = try await boards()
        guard generation == token else { throw FiestaBoardError.staleSession }
        knownBoards = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0) })
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
        let page: Page = try await fetch(APIRequest(path: ["v1", "pages", id]))
        guard page.id == id else { throw FiestaBoardError.invalidResponse }
        return page
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

    private func validateTarget(_ target: BoardTarget) throws {
        guard target.deployment == deployment else { throw FiestaBoardError.invalidTarget }
    }
    private func requireWrites(_ target: BoardTarget) throws {
        try validateTarget(target)
        guard access == .candidateWrites else { throw FiestaBoardError.writesDisabled }
        guard knownBoards[target.boardID] != nil else { throw FiestaBoardError.invalidTarget }
    }
    private func response(_ request: APIRequest) async throws -> APIResponse {
        let token = generation
        do {
            let result = try await transport.send(request)
            guard token == generation else { throw FiestaBoardError.staleSession }
            return result
        } catch {
            guard token == generation else { throw FiestaBoardError.staleSession }
            if (error as? FiestaBoardError) == .unauthenticated { access = .readOnly }
            throw (error as? FiestaBoardError) ?? (request.isMutation ? .unknownMutationOutcome : .networkUnavailable)
        }
    }
    private func fetch<T: Decodable & Sendable>(_ request: APIRequest) async throws -> T {
        let response = try await response(request)
        do { return try JSONDecoder().decode(T.self, from: response.data) }
        catch { throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .invalidResponse }
    }
}
