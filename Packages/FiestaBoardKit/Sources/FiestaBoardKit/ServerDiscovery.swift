import Foundation
import Network

public struct DiscoveredServer: Sendable, Identifiable, Equatable {
    public let deployment: DeploymentURL
    public let identity: ServerIdentity
    public let displayName: String
    public var id: String { deployment.description }
    public init(deployment: DeploymentURL, identity: ServerIdentity, displayName: String) {
        self.deployment = deployment; self.identity = identity; self.displayName = displayName
    }
}

public protocol ServerDiscovering: Sendable {
    /// Verified additions/changes only. Use snapshots for a picker that must reflect removals.
    func candidates() -> AsyncThrowingStream<DiscoveredServer, Error>
    /// Authoritative current results, including empty snapshots when advertisements disappear.
    func snapshots() -> AsyncThrowingStream<[DiscoveredServer], Error>
}

public enum ServerDiscoveryError: Error, Sendable, Equatable, LocalizedError {
    case unavailable, timedOut, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Local discovery is unavailable. Check Wi-Fi and the app's Local Network setting, or enter the server address manually."
        case .timedOut: "The advertised server did not respond in time. You can enter its address manually."
        case .invalidResponse: "The advertised server did not return a valid FiestaBoard identity."
        }
    }
}

struct BonjourAdvertisement: Sendable, Equatable {
    let id: String
    let name: String
    let serviceType: String
    let txt: [String: String]
    let endpoint: NWEndpoint
    var isFiestaBoard: Bool { serviceType == "_http._tcp" && txt["product"] == "FiestaBoard" && txt["path"] == "/" }
}

/// Every invocation owns its browser and anonymous verification requests. No results are persisted here.
public final class BonjourServerDiscovery: ServerDiscovering, Sendable {
    private let advertisements: @Sendable () -> AsyncThrowingStream<[BonjourAdvertisement], Error>
    private let resolve: @Sendable (BonjourAdvertisement) async throws -> DeploymentURL
    private let verify: @Sendable (DeploymentURL) async throws -> ServerIdentity
    private let verificationTimeout: Duration
    private let maximumConcurrentVerifications: Int

    public init(browseDuration: Duration = .seconds(12), verificationTimeout: Duration = .seconds(4), maximumConcurrentVerifications: Int = 3) {
        self.advertisements = { NetworkBonjourBrowser.stream(duration: max(.milliseconds(1), browseDuration)) }
        self.resolve = { try await NetworkBonjourResolver.resolve($0) }
        self.verify = { try await AnonymousDiscoveryVerifier.verify($0) }
        self.verificationTimeout = max(.milliseconds(1), verificationTimeout)
        self.maximumConcurrentVerifications = max(1, min(8, maximumConcurrentVerifications))
    }

    init(advertisements: @escaping @Sendable () -> AsyncThrowingStream<[BonjourAdvertisement], Error>,
         resolve: @escaping @Sendable (BonjourAdvertisement) async throws -> DeploymentURL,
         verify: @escaping @Sendable (DeploymentURL) async throws -> ServerIdentity,
         verificationTimeout: Duration, maximumConcurrentVerifications: Int) {
        self.advertisements = advertisements; self.resolve = resolve; self.verify = verify
        self.verificationTimeout = max(.milliseconds(1), verificationTimeout)
        self.maximumConcurrentVerifications = max(1, min(8, maximumConcurrentVerifications))
    }

    public func candidates() -> AsyncThrowingStream<DiscoveredServer, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var previous: [String: DiscoveredServer] = [:]
                do {
                    for try await snapshot in snapshots() {
                        let current = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
                        for server in snapshot where previous[server.id] != server { continuation.yield(server) }
                        previous = current
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func snapshots() -> AsyncThrowingStream<[DiscoveredServer], Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let run = DiscoveryRun(continuation: continuation, resolve: resolve, verify: verify,
                                   timeout: verificationTimeout, limit: maximumConcurrentVerifications)
            let task = Task {
                await withTaskCancellationHandler {
                    await run.begin()
                    do {
                        try Task.checkCancellation()
                        for try await snapshot in advertisements() {
                            try Task.checkCancellation()
                            await run.update(snapshot)
                        }
                        await run.sourceFinished()
                    } catch { await run.stop(error: error) }
                } onCancel: { Task { await run.stop(error: CancellationError()) } }
            }
            continuation.onTermination = { _ in task.cancel(); Task { await run.stop(error: nil) } }
        }
    }

    static func deployment(host: String, port: Int, path: String) throws -> DeploymentURL {
        guard path == "/", (1...65535).contains(port) else { throw FiestaBoardError.invalidDeployment }
        var unbracketed = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        // DNS-SD may return an absolute DNS name with its terminal root dot.
        if unbracketed.hasSuffix("."), !unbracketed.contains(":") { unbracketed.removeLast() }
        let authority = unbracketed.contains(":") ? "[\(unbracketed)]" : unbracketed
        return try DeploymentURL("http://\(authority):\(port)", allowLocalHTTP: true)
    }
}

private actor DiscoveryRun {
    let continuation: AsyncThrowingStream<[DiscoveredServer], Error>.Continuation
    let resolve: @Sendable (BonjourAdvertisement) async throws -> DeploymentURL
    let verify: @Sendable (DeploymentURL) async throws -> ServerIdentity
    let timeout: Duration
    let limit: Int
    var current: [String: BonjourAdvertisement] = [:]
    var verified: [String: DiscoveredServer] = [:]
    // Active tasks include invalidated generations until cancellation and resource cleanup finish.
    var active: [UUID: Task<Void, Never>] = [:]
    var generations: [String: UUID] = [:]
    var attempted: Set<String> = []
    var finished = false
    var stopped = false
    var last: [DiscoveredServer]?
    init(continuation: AsyncThrowingStream<[DiscoveredServer], Error>.Continuation,
         resolve: @escaping @Sendable (BonjourAdvertisement) async throws -> DeploymentURL,
         verify: @escaping @Sendable (DeploymentURL) async throws -> ServerIdentity, timeout: Duration, limit: Int) {
        self.continuation = continuation; self.resolve = resolve; self.verify = verify; self.timeout = timeout; self.limit = limit
    }
    func begin() { emit() }
    func update(_ snapshot: [BonjourAdvertisement]) {
        guard !stopped else { return }
        var next: [String: BonjourAdvertisement] = [:]
        for advertisement in snapshot where advertisement.isFiestaBoard { next[advertisement.id] = advertisement }
        for (id, old) in current where next[id] != old {
            if let token = generations.removeValue(forKey: id) { active[token]?.cancel() }
            verified.removeValue(forKey: id)
            attempted.remove(id)
        }
        current = next
        emit(); schedule()
    }
    func sourceFinished() { finished = true; completeIfIdle() }
    func stop(error: (any Error)?) {
        guard !stopped else { return }
        stopped = true
        for task in active.values { task.cancel() }
        generations.removeAll()
        continuation.finish(throwing: error)
    }
    func schedule() {
        guard !stopped else { return }
        for id in current.keys.sorted() where active.count < limit && !attempted.contains(id) {
            guard let advertisement = current[id] else { continue }
            attempted.insert(id)
            let token = UUID()
            let resolve = self.resolve, verify = self.verify, timeout = self.timeout
            let task = Task {
                var server: DiscoveredServer?
                do {
                    server = try await withDiscoveryTimeout(timeout) {
                        let deployment = try await resolve(advertisement)
                        try Task.checkCancellation()
                        let identity = try await verify(deployment)
                        try Task.checkCancellation()
                        return DiscoveredServer(deployment: deployment, identity: identity,
                            displayName: identity.name.isEmpty ? advertisement.name : identity.name)
                    }
                } catch { /* Unreachable, wrong-product, and stale advertisements are not candidates. */ }
                completed(id: id, token: token, server: server)
            }
            generations[id] = token
            active[token] = task
        }
    }
    func completed(id: String, token: UUID, server: DiscoveredServer?) {
        active.removeValue(forKey: token)
        guard !stopped else { return }
        if generations[id] == token {
            generations.removeValue(forKey: id)
            if let server { verified[id] = server }
        }
        emit(); schedule(); completeIfIdle()
    }
    func completeIfIdle() { if finished && active.isEmpty { stop(error: nil) } }
    func emit() {
        let ordered = verified.keys.sorted().compactMap { verified[$0] }
        var unique: [String: DiscoveredServer] = [:]
        for server in ordered where unique[server.id] == nil { unique[server.id] = server }
        let snapshot = unique.values.sorted { $0.id < $1.id }
        if last != snapshot { last = snapshot; continuation.yield(snapshot) }
    }
}

private func withDiscoveryTimeout<T: Sendable>(_ timeout: Duration, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: timeout); throw ServerDiscoveryError.timedOut }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw CancellationError() }
        return value
    }
}

/// Synchronously records Network's serial callbacks before any task/actor hop.
/// Stream buffering preserves a preceding removal when a terminal callback immediately follows it.
struct BonjourCallbackStream: Sendable {
    let snapshots: AsyncThrowingStream<[BonjourAdvertisement], Error>
    let continuation: AsyncThrowingStream<[BonjourAdvertisement], Error>.Continuation
    init() {
        let (stream, continuation) = AsyncThrowingStream<[BonjourAdvertisement], Error>.makeStream()
        self.snapshots = stream; self.continuation = continuation
    }
    func publish(_ snapshot: [BonjourAdvertisement]) { continuation.yield(snapshot) }
    func finish(error: (any Error)? = nil) { continuation.finish(throwing: error) }
}

private actor NetworkBonjourBrowser {
    let callbacks: BonjourCallbackStream
    var browser: NWBrowser?
    var deadline: Task<Void, Never>?
    var stopped = false
    init(_ callbacks: BonjourCallbackStream) { self.callbacks = callbacks }
    static func stream(duration: Duration) -> AsyncThrowingStream<[BonjourAdvertisement], Error> {
        let callbacks = BonjourCallbackStream()
        let session = NetworkBonjourBrowser(callbacks)
        callbacks.continuation.onTermination = { _ in Task { await session.stop(error: nil) } }
        Task { await session.start(duration: duration) }
        return callbacks.snapshots
    }
    func start(duration: Duration) {
        guard !stopped else { return }
        let callbacks = self.callbacks
        let queue = DispatchQueue(label: "FiestaBoard.discovery")
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_http._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in
            let snapshot = results.compactMap { result -> BonjourAdvertisement? in
                guard case .service(let name, let type, let domain, _) = result.endpoint,
                      case .bonjour(let txt) = result.metadata else { return nil }
                return BonjourAdvertisement(id: "\(name).\(type).\(domain)", name: name, serviceType: type,
                    txt: ["product": txt["product"] ?? "", "path": txt["path"] ?? ""], endpoint: result.endpoint)
            }
            callbacks.publish(snapshot)
        }
        browser.stateUpdateHandler = { state in
            switch state {
            case .failed, .waiting: callbacks.finish(error: ServerDiscoveryError.unavailable)
            default: break
            }
        }
        self.browser = browser
        browser.start(queue: queue)
        deadline = Task {
            do {
                try await Task.sleep(for: duration)
                queue.async { callbacks.finish() }
            } catch {}
        }
    }
    func stop(error: (any Error)?) {
        guard !stopped else { return }
        stopped = true; browser?.cancel(); browser = nil
        deadline?.cancel(); deadline = nil
        callbacks.finish(error: error)
    }
}

private actor NetworkBonjourResolver {
    var connection: NWConnection?
    var continuation: CheckedContinuation<DeploymentURL, any Error>?
    var stopped = false
    static func resolve(_ advertisement: BonjourAdvertisement) async throws -> DeploymentURL {
        let resolver = NetworkBonjourResolver()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await resolver.start(advertisement)
        } onCancel: { Task { await resolver.finish(.failure(CancellationError())) } }
    }
    func start(_ advertisement: BonjourAdvertisement) async throws -> DeploymentURL {
        guard !stopped else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let connection = NWConnection(to: advertisement.endpoint, using: .tcp)
            self.connection = connection
            connection.stateUpdateHandler = { state in Task { await self.state(state, path: connection.currentPath) } }
            connection.start(queue: DispatchQueue(label: "FiestaBoard.discovery.resolve"))
        }
    }
    func state(_ state: NWConnection.State, path: NWPath?) {
        switch state {
        case .ready:
            guard case .hostPort(let host, let port) = path?.remoteEndpoint else {
                finish(.failure(ServerDiscoveryError.invalidResponse)); return
            }
            do { finish(.success(try BonjourServerDiscovery.deployment(host: "\(host)", port: Int(port.rawValue), path: "/"))) }
            catch { finish(.failure(error)) }
        case .failed, .waiting: finish(.failure(ServerDiscoveryError.unavailable))
        case .cancelled: finish(.failure(CancellationError()))
        default: break
        }
    }
    func finish(_ result: Result<DeploymentURL, any Error>) {
        guard !stopped else { return }
        stopped = true
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        continuation?.resume(with: result); continuation = nil
    }
}

/// A separate, ephemeral session prevents any connection account's cookies or credentials crossing into browsing.
enum AnonymousDiscoveryVerifier {
    static func verify(_ deployment: DeploymentURL, protocolClasses: [AnyClass]? = nil) async throws -> ServerIdentity {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        configuration.protocolClasses = protocolClasses
        let session = URLSession(configuration: configuration, delegate: NoDiscoveryRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let url = try deployment.apiURL(["discover"])
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url else { throw ServerDiscoveryError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 65_536 else { throw ServerDiscoveryError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try JSONDecoder().decode(ServerIdentity.self, from: data)
    }
}

private final class NoDiscoveryRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
