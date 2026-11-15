import Foundation

/// Proof is scoped to a single request and is never stored or logged.
public enum APIRequestContext: Sendable {
    case standard
    case onboardingToken(String)
    case browserSession(origin: String, csrfToken: String)
}
public enum APIRequestCachePolicy: Sendable { case `default`, noStore }

public struct APIRequest: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }
    public let method: Method
    public let path: [String]
    public let body: Data?
    public let queryItems: [URLQueryItem]
    public let timeout: TimeInterval
    public let context: APIRequestContext
    public let cachePolicy: APIRequestCachePolicy
    /// The bounded evaluation POSTs (and the page-thumbnail batch render) never
    /// write a page or send to hardware.
    public var isMutation: Bool {
        method != .get && !(method == .post && (path == ["templates", "validate"] || path == ["templates", "render"] || path == ["pages", "preview", "flexible"] || path == ["pages", "preview", "batch"]))
    }
    public init(_ method: Method = .get, path: [String], body: Data? = nil, timeout: TimeInterval = 20, queryItems: [URLQueryItem] = [], context: APIRequestContext = .standard, cachePolicy: APIRequestCachePolicy = .default) {
        self.method = method; self.path = path; self.body = body; self.timeout = timeout; self.queryItems = queryItems
        self.context = context; self.cachePolicy = cachePolicy
    }
}
public struct APIResponse: Sendable {
    public let status: Int
    public let data: Data
    public init(status: Int, data: Data) { self.status = status; self.data = data }
}
public protocol APITransport: Sendable {
    func send(_ request: APIRequest) async throws -> APIResponse
    func resetSession() async
    func beginSessionRevocation() async
    func configureSessionPersistence(rememberMe: Bool, installationID: String?) async
    func restoreRememberedSession(observedInstallationID: String) async -> Bool
    func forgetRememberedSession() async
    func sessionPersistenceState() async -> SessionPersistenceState
    func provisionalConnectionID() async -> UUID?
    func verifyConnectionID(_ proposed: UUID, installationID: String) async -> UUID?
    func ownsConnectionID(_ id: UUID) async -> Bool
}
public extension APITransport {
    /// Custom transports without queued work need no retirement action.
    func beginSessionRevocation() async {}
    func provisionalConnectionID() async -> UUID? { nil }
    func verifyConnectionID(_ proposed: UUID, installationID: String) async -> UUID? { proposed }
    func ownsConnectionID(_ id: UUID) async -> Bool { true }
    func configureSessionPersistence(rememberMe: Bool, installationID: String?) async {}
    func restoreRememberedSession(observedInstallationID: String) async -> Bool { false }
    func forgetRememberedSession() async {}
    func sessionPersistenceState() async -> SessionPersistenceState { .init() }
}
/// Memory-only by default, isolated to one full deployment identity; never uses a shared cookie or credential store.
public actor URLSessionTransport: APITransport {
    private let requestBudget: HubRequestBudget?
    private let deployment: DeploymentURL
    private let session: URLSession
    private var mobileSession: MobileSession?
    public private(set) var lastServerDate: Date?
    private var revoking = false
    private var generation: UInt64 = 0
    private let vault: (any SessionVault)?
    private let coordinator: any SessionVaultCoordinating
    private var lease: SessionVaultCoordinator.Lease?
    private var persistence = SessionPersistenceState()
    private var persistenceEpoch: UInt64 = 0
    private var installationID: String?
    private var connectionID: UUID?

    public init(deployment: DeploymentURL, protocolClasses: [AnyClass] = [], vault: (any SessionVault)? = nil, requestBudget: HubRequestBudget? = nil) {
        self.deployment = deployment
        self.requestBudget = requestBudget
        self.vault = vault
        coordinator = SessionVaultCoordinator.shared
        session = Self.makeSession(protocolClasses: protocolClasses)
    }

    init(deployment: DeploymentURL, protocolClasses: [AnyClass], vault: any SessionVault, coordinator: any SessionVaultCoordinating) {
        self.deployment = deployment
        self.vault = vault
        requestBudget = nil
        self.coordinator = coordinator
        session = Self.makeSession(protocolClasses: protocolClasses)
    }

    private nonisolated static func makeSession(protocolClasses: [AnyClass]) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration, delegate: RefuseRedirectDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func resetSession() {
        revoking = false
        generation &+= 1
        mobileSession = nil
        connectionID = nil
        persistence.restored = false
    }

    /// Retire already queued work before self-revoke waits for a budget slot.
    /// Keep the bearer available exclusively for DELETE /auth/device/session.
    public func beginSessionRevocation() {
        generation &+= 1
        revoking = true
    }

    /// Consent is a new ownership transition; even a memory-only replacement clears old material.
    public func configureSessionPersistence(rememberMe: Bool, installationID: String?) async {
        persistenceEpoch &+= 1
        let epoch = persistenceEpoch
        persistence = .init(rememberMe: rememberMe)
        self.installationID = Self.validIdentity(installationID)
        connectionID = UUID()
        guard let vault else {
            if rememberMe { persistence.warning = .unavailable }
            return
        }
        let token = generation
        let newLease = await coordinator.claim(vault, for: deployment, replacing: true)
        guard token == generation, epoch == persistenceEpoch else { return }
        lease = newLease
        do { _ = try await coordinator.perform(newLease) { try await vault.remove(for: self.deployment); return nil } }
        catch { if token == generation && epoch == persistenceEpoch { persistence.warning = .unavailable; persistence.cleanupPending = true } }
    }

    public func sessionPersistenceState() async -> SessionPersistenceState { persistence }

    public func restoreRememberedSession(observedInstallationID: String) async -> Bool {
        persistenceEpoch &+= 1
        let epoch = persistenceEpoch
        let token = generation
        guard let identity = Self.validIdentity(observedInstallationID) else {
            persistence.warning = .identityRequired; return false
        }
        guard let vault else { return false }
        let newLease = await coordinator.claim(vault, for: deployment, replacing: false)
        guard token == generation, epoch == persistenceEpoch else { return false }
        lease = newLease
        do {
            let data = try await coordinator.perform(newLease) { try await vault.load(for: self.deployment) }
            let currentOwner = await coordinator.isCurrent(newLease)
            // The ownership query is an actor hop: local logout/forget/reset may
            // run after its result is computed and before this actor resumes.
            guard token == generation, epoch == persistenceEpoch, currentOwner else { return false }
            guard let data else { return false }
            guard let restored = MobileSession.restore(data, deployment: deployment, installationID: identity) else {
                persistence.warning = .invalidStoredSession; return false
            }
            mobileSession = restored
            connectionID = MobileSession.storedConnectionID(data)
            installationID = identity
            persistence = .init(rememberMe: true, restored: true)
            return true
        } catch {
            if token == generation && epoch == persistenceEpoch { persistence.warning = .unavailable }
            return false
        }
    }

    public func forgetRememberedSession() async {
        persistenceEpoch &+= 1
        let epoch = persistenceEpoch
        persistence = .init()
        installationID = nil
        let token = generation
        guard let vault else { return }
        let owner: SessionVaultCoordinator.Lease
        if let lease { owner = lease }
        else { owner = await coordinator.claim(vault, for: deployment, replacing: false) }
        // Retire this owner's pending writes without stealing a newer window's credential.
        guard let replacement = await coordinator.retire(owner), epoch == persistenceEpoch else { return }
        lease = replacement
        do { _ = try await coordinator.perform(replacement) { try await vault.remove(for: self.deployment); return nil } }
        catch { if token == generation && epoch == persistenceEpoch { persistence.warning = .unavailable; persistence.cleanupPending = true } }
    }

    public func provisionalConnectionID() -> UUID? { connectionID }

    /// The UUID imported from disk is provisional until the service has verified discovery and auth.
    public func verifyConnectionID(_ proposed: UUID, installationID verifiedInstallation: String) async -> UUID? {
        let token = generation, epoch = persistenceEpoch
        if let lease, !(await coordinator.isCurrent(lease)) { return nil }
        guard token == generation, epoch == persistenceEpoch else { return nil }
        let migrating = connectionID == nil && persistence.restored
        var confirmed = proposed
        self.installationID = Self.validIdentity(verifiedInstallation)
        if migrating, let installationID, let vault, let lease {
            // Serialize migration with other windows. A second verified importer uses
            // the UUID already committed by the first, rather than minting another identity.
            let candidate = mobileSession?.persisted(deployment: deployment, installationID: installationID, connectionID: proposed)
            do {
                let committed = try await coordinator.perform(lease) {
                    if let existing = try await vault.load(for: self.deployment),
                       MobileSession.restore(existing, deployment: self.deployment, installationID: installationID) != nil,
                       MobileSession.storedConnectionID(existing) != nil { return existing }
                    if let candidate { try await vault.save(candidate, for: self.deployment) }
                    return candidate
                }
                guard token == generation, epoch == persistenceEpoch else { return nil }
                if let committed, let existingID = MobileSession.storedConnectionID(committed) { confirmed = existingID }
            } catch {
                guard token == generation, epoch == persistenceEpoch else { return nil }
                persistence.warning = .unavailable
            }
        }
        guard token == generation, epoch == persistenceEpoch else { return nil }
        connectionID = confirmed
        if !migrating { await persistCredential(generation: token, epoch: epoch) }
        guard token == generation, epoch == persistenceEpoch, connectionID == confirmed else { return nil }
        if let lease {
            let current = await coordinator.isCurrent(lease)
            guard current, token == generation, epoch == persistenceEpoch, connectionID == confirmed else { return nil }
        }
        return confirmed
    }

    public func ownsConnectionID(_ id: UUID) async -> Bool {
        let token = generation, epoch = persistenceEpoch
        guard connectionID == id else { return false }
        if let lease {
            let current = await coordinator.isCurrent(lease)
            return current && token == generation && epoch == persistenceEpoch && connectionID == id
        }
        return true
    }

    private static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    private static func validIdentity(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= 256, !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
        return value
    }

    private func persistCredential(generation token: UInt64, epoch: UInt64) async {
        guard epoch == persistenceEpoch, persistence.rememberMe else { return }
        guard let installationID else { persistence.warning = .identityRequired; return }
        guard let vault, let lease else { persistence.warning = .unavailable; return }
        // A v1 import is not migrated until the service verifies it.
        guard let connectionID else { return }
        guard let data = mobileSession?.persisted(deployment: deployment, installationID: installationID, connectionID: connectionID) else {
            persistence.warning = .noCredential
            do { _ = try await coordinator.perform(lease) { try await vault.remove(for: self.deployment); return nil } }
            catch { if token == generation && epoch == persistenceEpoch { persistence.warning = .unavailable; persistence.cleanupPending = true } }
            return
        }
        do {
            _ = try await coordinator.perform(lease) { try await vault.save(data, for: self.deployment); return nil }
            if token == generation && epoch == persistenceEpoch {
                let current = await coordinator.isCurrent(lease)
                if current && token == generation && epoch == persistenceEpoch { persistence.cleanupPending = false }
            }
        }
        catch { if token == generation && epoch == persistenceEpoch { persistence.warning = .unavailable } }
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        let queuedGeneration = generation
        let budget = if let requestBudget { requestBudget } else { await HubRequestBudgets.shared.budget(for: deployment) }
        return try await budget.run { try await self.performSend(request, expectedGeneration: queuedGeneration) }
    }

    private func performSend(_ request: APIRequest, expectedGeneration: UInt64) async throws -> APIResponse {
        guard expectedGeneration == generation, !revoking || (request.method == .delete && request.path == ["auth", "device", "session"]) else { throw FiestaBoardError.staleSession }
        try Task.checkCancellation()
        let headers = try request.boundedHeaders()
        let currentGeneration = generation
        let currentPersistenceEpoch = persistenceEpoch
        let baseURL = try deployment.apiURL(request.path)
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw FiestaBoardError.invalidPath }
        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
            // FastAPI treats query strings as form data: a literal plus must stay a plus.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw FiestaBoardError.invalidPath }
        var wire = URLRequest(url: url)
        wire.timeoutInterval = request.timeout
        wire.httpMethod = request.method.rawValue
        wire.httpBody = request.body
        wire.httpShouldHandleCookies = false
        for (name, value) in headers { wire.setValue(value, forHTTPHeaderField: name) }
        if request.cachePolicy == .noStore {
            wire.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            wire.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        }
        wire.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.body != nil { wire.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if case .standard = request.context {
            wire.setValue(mobileSession?.authorization, forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            // Exactly one application-level task, with no retry or mutation replay.
            (data, response) = try await session.data(for: wire)
        } catch {
            guard currentGeneration == generation else { throw FiestaBoardError.staleSession }
            if !request.isMutation && (Task.isCancelled || (error as? URLError)?.code == .cancelled) { throw CancellationError() }
            throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .networkUnavailable
        }
        guard currentGeneration == generation else { throw FiestaBoardError.staleSession }
        guard let http = response as? HTTPURLResponse else {
            throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .invalidResponse
        }
        lastServerDate = http.value(forHTTPHeaderField: "Date").flatMap(Self.httpDate)
        if (200..<300).contains(http.statusCode), request.method == .post,
           [ ["auth", "device", "login"], ["auth", "pairing", "claim"] ].contains(request.path) {
            guard let reply = try? JSONDecoder().decode(MobileTokenReply.self, from: data),
                  let credential = try? MobileSession(reply: reply) else { throw FiestaBoardError.unknownMutationOutcome }
            guard currentPersistenceEpoch == persistenceEpoch else { throw FiestaBoardError.staleSession }
            mobileSession = credential
            await persistCredential(generation: currentGeneration, epoch: currentPersistenceEpoch)
        }
        if http.statusCode == 401 && mobileSession != nil {
            mobileSession = nil
            generation &+= 1
            let signedOutGeneration = generation
            await forgetRememberedSession()
            guard signedOutGeneration == generation else { throw FiestaBoardError.staleSession }
            throw FiestaBoardError.unauthenticated
        }
        guard currentGeneration == generation else { throw FiestaBoardError.staleSession }
        let canBeGateway = (200..<300).contains(http.statusCode) || (500..<600).contains(http.statusCode)
        if canBeGateway && (http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/html") == true ||
            data.first(where: { ![9, 10, 13, 32].contains($0) }) == 60) {
            throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .gatewayUnavailable
        }
        if let error = request.safeError(status: http.statusCode, data: data) { throw error }
        switch http.statusCode {
        case 200..<300: return APIResponse(status: http.statusCode, data: data)
        case 300..<400: throw request.isMutation ? FiestaBoardError.unknownMutationOutcome : .redirectRefused
        case 401: throw FiestaBoardError.unauthenticated
        case 412: throw request.path.starts(with: ["v1", "collections"]) ? FiestaBoardError.collectionConflict : .pageConflict
        case 409: throw request.method == .delete && request.path.starts(with: ["v1", "collections"]) ? FiestaBoardError.collectionInUse : .conflict
        case 429:
            let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap { value -> Int? in
                if let seconds = Int(value), seconds >= 0 { return seconds }
                guard let target = Self.httpDate(value) else { return nil }
                return max(0, Int(ceil(target.timeIntervalSince(lastServerDate ?? Date()))))
            }
            throw FiestaBoardError.rateLimited(retryAfterSeconds: seconds)
        case 502:
            struct Partial: Decodable {
                struct Detail: Decodable { let partial: Bool; let failed_regions: [FailedRegion] }
                let detail: Detail
            }
            if let partial = try? JSONDecoder().decode(Partial.self, from: data), partial.detail.partial {
                throw FiestaBoardError.partialWrite(failedRegions: partial.detail.failed_regions)
            }
            if request.isMutation { throw FiestaBoardError.unknownMutationOutcome }
            throw FiestaBoardError.rejected(status: 502)
        case 500...599 where request.isMutation: throw FiestaBoardError.unknownMutationOutcome
        default: throw FiestaBoardError.rejected(status: http.statusCode)
        }
    }
}

final class RefuseRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Use system TLS trust validation; never answer HTTP credential challenges.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}

extension APIRequest {
    private func headerValueIsSafe(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 >= 33 && $0 <= 126 }
    }
    func boundedHeaders() throws -> [String: String] {
        switch context {
        case .standard: return [:]
        case .onboardingToken(let token):
            let setup = method == .post && path == ["auth", "setup"]
            let preference = method == .post && path == ["auth", "preference"] &&
                body.flatMap { try? JSONDecoder().decode(EnabledPreference.self, from: $0).enabled } == true
            guard (setup || preference), headerValueIsSafe(token) else { throw FiestaBoardError.invalidRequestContext }
            return ["Authorization": "Bearer " + token]
        case .browserSession(let origin, let csrfToken):
            guard isMutation, headerValueIsSafe(origin), headerValueIsSafe(csrfToken),
                  let parts = URLComponents(string: origin), ["http", "https"].contains(parts.scheme),
                  parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
                  parts.path.isEmpty, parts.query == nil, parts.fragment == nil else { throw FiestaBoardError.invalidRequestContext }
            return ["Origin": origin, "X-CSRF-Token": csrfToken]
        }
    }
    private struct EnabledPreference: Decodable { let enabled: Bool }
    func safeError(status: Int, data: Data) -> FiestaBoardError? {
        guard status >= 400 else { return nil }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let detail = object?["detail"] as? String
        let authEndpoint = path.count == 2 && path.first == "auth"
        if status == 401 && ([ ["auth", "login"], ["auth", "device", "login"] ].contains(path)) && (detail == "Invalid username or password" || object?["error"] as? String == "invalid_credentials") { return .invalidCredentials }
        if status == 403 {
            if [ ["auth", "setup"], ["auth", "preference"] ].contains(path),
               detail == "This install has a stored MCP token. Present it as a Bearer token to enable login, or clear the token first." { return .setupProofRequired }
            if object?["error"] as? String == "forbidden" && detail == "Refresh this page and try again." { return .csrfRequired }
            return .forbidden
        }
        if status == 409 {
            if object?["setup_required"] as? Bool == true || (path == ["auth", "login"] && detail == "No user has been created. Call /auth/setup first.") {
                return .setupRequired(firstRun: object?["first_run"] as? Bool ?? false)
            }
            if authEndpoint && detail == "Auth mode is pinned by FIESTABOARD_AUTH_ENABLED." { return .onboardingConflict(.modePinned) }
            if authEndpoint && ["Already set up", "A user has already been created. Use /auth/login.", "A user already exists. Sign in and use the account settings to change preferences."].contains(detail ?? "") { return .onboardingConflict(.alreadySetUp) }
        }
        if status == 422 {
            let entries = object?["detail"] as? [[String: Any]] ?? []
            let fields = entries.compactMap { entry -> ValidationField? in
                guard let location = entry["loc"] as? [String], location.count == 2, location[0] == "body" else { return nil }
                return ValidationField(rawValue: location[1])
            }
            return .validation(fields: Array(Set(fields)).sorted { $0.rawValue < $1.rawValue })
        }
        if status == 503 && !isMutation { return .startupUnavailable }
        return nil
    }
}
