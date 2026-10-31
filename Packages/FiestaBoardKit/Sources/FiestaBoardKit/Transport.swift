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
    /// The two bounded evaluation POSTs never write a page or send to hardware.
    public var isMutation: Bool {
        method != .get && !(method == .post && (path == ["templates", "validate"] || path == ["templates", "render"] || path == ["pages", "preview", "flexible"]))
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
    func configureSessionPersistence(rememberMe: Bool, installationID: String?) async
    func restoreRememberedSession(observedInstallationID: String) async -> Bool
    func forgetRememberedSession() async
    func sessionPersistenceState() async -> SessionPersistenceState
    func provisionalConnectionID() async -> UUID?
    func verifyConnectionID(_ proposed: UUID, installationID: String) async -> UUID?
    func ownsConnectionID(_ id: UUID) async -> Bool
}
public extension APITransport {
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
    private let deployment: DeploymentURL
    private let session: URLSession
    private var cookies = SessionCookieJar()
    private var generation: UInt64 = 0
    private let vault: (any SessionVault)?
    private let coordinator: any SessionVaultCoordinating
    private var lease: SessionVaultCoordinator.Lease?
    private var persistence = SessionPersistenceState()
    private var persistenceEpoch: UInt64 = 0
    private var installationID: String?
    private var connectionID: UUID?

    public init(deployment: DeploymentURL, protocolClasses: [AnyClass] = [], vault: (any SessionVault)? = nil) {
        self.deployment = deployment
        self.vault = vault
        coordinator = SessionVaultCoordinator.shared
        session = Self.makeSession(protocolClasses: protocolClasses)
    }

    init(deployment: DeploymentURL, protocolClasses: [AnyClass], vault: any SessionVault, coordinator: any SessionVaultCoordinating) {
        self.deployment = deployment
        self.vault = vault
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
        generation &+= 1
        cookies = SessionCookieJar()
        connectionID = nil
        persistence.restored = false
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
            guard let restored = SessionCookieJar.restore(data, deployment: deployment, installationID: identity) else {
                persistence.warning = .invalidStoredSession; return false
            }
            cookies = restored
            connectionID = SessionCookieJar.storedConnectionID(data)
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
            let candidate = cookies.persisted(deployment: deployment, installationID: installationID, connectionID: proposed)
            do {
                let committed = try await coordinator.perform(lease) {
                    if let existing = try await vault.load(for: self.deployment),
                       SessionCookieJar.restore(existing, deployment: self.deployment, installationID: installationID) != nil,
                       SessionCookieJar.storedConnectionID(existing) != nil { return existing }
                    if let candidate { try await vault.save(candidate, for: self.deployment) }
                    return candidate
                }
                guard token == generation, epoch == persistenceEpoch else { return nil }
                if let committed, let existingID = SessionCookieJar.storedConnectionID(committed) { confirmed = existingID }
            } catch {
                guard token == generation, epoch == persistenceEpoch else { return nil }
                persistence.warning = .unavailable
            }
        }
        guard token == generation, epoch == persistenceEpoch else { return nil }
        connectionID = confirmed
        if !migrating { await persistCookies(generation: token, epoch: epoch) }
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

    private static func validIdentity(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= 256, !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
        return value
    }

    private func persistCookies(generation token: UInt64, epoch: UInt64) async {
        guard epoch == persistenceEpoch, persistence.rememberMe else { return }
        guard let installationID else { persistence.warning = .identityRequired; return }
        guard let vault, let lease else { persistence.warning = .unavailable; return }
        // A v1 import is not migrated until the service verifies it.
        guard let connectionID else { return }
        guard let data = cookies.persisted(deployment: deployment, installationID: installationID, connectionID: connectionID) else {
            persistence.warning = .noPersistentCookie
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
        wire.setValue(cookies.header(for: url), forHTTPHeaderField: "Cookie")
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
        if let header = http.value(forHTTPHeaderField: "Set-Cookie") {
            cookies.receive(header, from: url)
            if (200..<300).contains(http.statusCode) { await persistCookies(generation: currentGeneration, epoch: currentPersistenceEpoch) }
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
            let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil }
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

struct SessionCookieJar: Sendable {
    private struct Cookie: Sendable, Codable {
        let name: String
        let value: String
        let domain: String
        let hostOnly: Bool
        let path: String
        let secure: Bool
        let expires: Date?
    }
    private var entries: [Cookie] = []

    mutating func receive(_ header: String, from url: URL, now: Date = Date()) {
        // Split combined Set-Cookie fields only at the next cookie name, not an Expires comma.
        let pattern = ",(?=\\s*[^;,=\\s]+\\s*=)"
        let fields = header.replacingOccurrences(of: pattern, with: "\n", options: .regularExpression).split(separator: "\n")
        guard let host = url.host?.lowercased() else { return }
        for field in fields {
            let attributes = field.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = attributes.first, let equals = first.firstIndex(of: "="),
                  first[..<equals] == "fiestaboard_session" else { continue }
            let value = String(first[first.index(after: equals)...])
            guard value.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 && $0 != 59 && $0 != 44 }) else { continue }
            var domain = host
            var hostOnly = true
            var path = String(url.path.prefix(through: url.path.lastIndex(of: "/") ?? url.path.startIndex).dropLast())
            if path.isEmpty { path = "/" }
            var secure = false
            var expiry: Date?
            var maxAge: Int?
            for attribute in attributes.dropFirst() {
                let pair = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = pair[0].lowercased()
                let val = pair.count == 2 ? String(pair[1]) : ""
                switch key {
                case "domain": domain = val.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")); hostOnly = false
                case "path": if val.hasPrefix("/") { path = val }
                case "secure": secure = true
                case "max-age": maxAge = Int(val)
                default: break
                }
            }
            // This draft accepts explicit domains only equal to the deployment host.
            // It intentionally refuses parent-domain cookies, avoiding public-suffix ambiguity.
            guard domain == host else { continue }
            if let maxAge { expiry = now.addingTimeInterval(TimeInterval(maxAge)) }
            else {
                expiry = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": String(field)], for: url).first?.expiresDate
            }
            entries.removeAll { $0.domain == domain && $0.path == path }
            if expiry.map({ $0 <= now }) ?? false { continue }
            entries.append(Cookie(name: "fiestaboard_session", value: value, domain: domain, hostOnly: hostOnly, path: path, secure: secure, expires: expiry))
        }
    }

    private struct StoredSession: Codable {
        let version: Int
        let deployment: String
        let installationID: String
        let cookies: [Cookie]
        let connectionID: UUID?
    }
    func persisted(deployment: DeploymentURL, installationID: String, connectionID: UUID, now: Date = Date()) -> Data? {
        let persistent = entries.filter { $0.expires.map { $0 > now } ?? false }
        guard !persistent.isEmpty, persistent.count <= 16 else { return nil }
        return try? JSONEncoder().encode(StoredSession(version: 2, deployment: deployment.description,
            installationID: installationID, cookies: persistent, connectionID: connectionID))
    }
    static func storedConnectionID(_ data: Data) -> UUID? {
        guard let stored = try? JSONDecoder().decode(StoredSession.self, from: data), stored.version == 2 else { return nil }
        return stored.connectionID
    }
    static func restore(_ data: Data, deployment: DeploymentURL, installationID: String, now: Date = Date()) -> Self? {
        guard data.count <= 65_536,
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data), [1, 2].contains(stored.version),
              (stored.version == 1 || stored.connectionID != nil),
              stored.deployment == deployment.description, stored.installationID == installationID,
              !stored.cookies.isEmpty, stored.cookies.count <= 16,
              let url = try? deployment.apiURL(["auth", "status"]), let host = url.host?.lowercased() else { return nil }
        var keys = Set<String>()
        for cookie in stored.cookies {
            guard cookie.name == "fiestaboard_session", cookie.domain == host,
                  cookie.path.hasPrefix("/"), cookie.path.utf8.count <= 2048,
                  cookie.path.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 && $0 != 59 && $0 != 44 }),
                  !cookie.value.isEmpty, cookie.value.utf8.count <= 8192,
                  cookie.value.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 && $0 != 59 && $0 != 44 }),
                  cookie.expires.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 > now }) == true,
                  !cookie.secure || url.scheme == "https",
                  keys.insert(cookie.domain + "\n" + cookie.path).inserted else { return nil }
        }
        var jar = Self(); jar.entries = stored.cookies
        guard jar.header(for: url, now: now) != nil else { return nil }
        return jar
    }

    func header(for url: URL, now: Date = Date()) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let matching = entries.filter { cookie in
            let domainMatches = host == cookie.domain || (!cookie.hostOnly && host.hasSuffix("." + cookie.domain))
            let path = url.path.isEmpty ? "/" : url.path
            let pathMatches = path == cookie.path || (path.hasPrefix(cookie.path) &&
                (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
            return domainMatches && pathMatches && (!cookie.secure || url.scheme == "https") &&
                (cookie.expires.map { $0 > now } ?? true)
        }.sorted { $0.path.count > $1.path.count }
        return matching.isEmpty ? nil : matching.map { "fiestaboard_session=" + $0.value }.joined(separator: "; ")
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
        if status == 401 && path == ["auth", "login"] && detail == "Invalid username or password" { return .invalidCredentials }
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
