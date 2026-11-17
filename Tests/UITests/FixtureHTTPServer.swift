import Foundation
import Network

/// Adapted from tvOS UITests/FixtureHTTPServer.swift (universal-tv).
/// Runs inside the test runner, bound only to loopback, with an OS-assigned port.
/// Its own serial queue owns request parsing and mutable per-namespace router state.
// Queue confinement protects mutable state across Network @Sendable callbacks.
final class FixtureHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "FiestaBoardUITests.nativeFixture")
    private let router: FixtureRouter
    private var dropped = false
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    var port: UInt16 { listener.port!.rawValue }
    func holdHomeMutations(_ held: Bool) { router.homeMutationGate.setHeld(held) }
    var homeMutationWaiting: Bool { router.homeMutationGate.isWaiting }
    func holdOnboardingBootstrap(_ held: Bool) { router.onboardingBootstrapGate.setHeld(held) }
    var onboardingBootstrapWaiting: Bool { router.onboardingBootstrapGate.isWaiting }
    func holdOnboardingHandoffPages(_ held: Bool) { router.onboardingHandoffPagesGate.setHeld(held) }
    var onboardingHandoffPagesWaiting: Bool { router.onboardingHandoffPagesGate.isWaiting }

    init(router: FixtureRouter) throws {
        self.router = router
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state { case .ready, .failed: ready.signal(); default: break }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now()+5) == .success, listener.port != nil else {
            listener.cancel(); throw NSError(domain: "FixtureHTTPServer", code: 1)
        }
    }
    enum ReadinessError: Error { case timeout, transport, badStatus, identityMismatch }

    static func validateReadyResponse(status: Int, body: Data) throws {
        guard status == 200 else { throw ReadinessError.badStatus }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["fixture"] as? String == "native-onboarding" else { throw ReadinessError.identityMismatch }
    }

    /// A broken in-process test dependency is a failure, never a skipped journey.
    func requireReady() throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/ready")!)
        request.timeoutInterval = 3
        let result = ReadinessResult()
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            result.set(error == nil ? .success(((response as? HTTPURLResponse)?.statusCode ?? -1, data ?? Data())) : .failure(ReadinessError.transport))
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 5) == .success else { task.cancel(); throw ReadinessError.timeout }
        let (status, body) = try result.get()
        try Self.validateReadyResponse(status: status, body: body)
    }

    private final class ReadinessResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<(Int, Data), Error>?
        func set(_ value: Result<(Int, Data), Error>) { lock.withLock { self.value = value } }
        func get() throws -> (Int, Data) {
            try lock.withLock { try value?.get() ?? { throw ReadinessError.transport }() }
        }
    }

    deinit { listener.cancel(); for connection in connections.values { connection.cancel() } }
    /// Drop subsequent requests like an unplugged hub, without returning fabricated HTTP errors.
    func setDropped(_ value: Bool) { queue.sync { dropped = value } }
    private func handle(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state { case .cancelled, .failed: self.connections.removeValue(forKey: ObjectIdentifier(connection)); default: break }
        }
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            if self.dropped { connection.cancel(); return }
            let bytes = accumulated + (data ?? Data())
            guard bytes.count <= 4*1024*1024 else { self.send(self.router.reply(413), to: connection); return }
            guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                if bytes.count > 16384 || complete || error != nil { self.send(self.router.reply(400), to: connection) }
                else { self.receive(connection, accumulated: bytes) }; return
            }
            guard boundary.lowerBound <= 16384, let head = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) else { self.send(self.router.reply(400), to: connection); return }
            let lines = head.components(separatedBy: "\r\n"), first = lines[0].split(separator: " ").map(String.init)
            guard first.count == 3 else { self.send(self.router.reply(400), to: connection); return }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { self.send(self.router.reply(400), to: connection); return }
                let key = line[..<colon].lowercased()
                guard headers[key] == nil else { self.send(self.router.reply(400), to: connection); return }
                headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            guard headers["transfer-encoding"] == nil, let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= 4*1024*1024 else { self.send(self.router.reply(400), to: connection); return }
            let content = Data(bytes[boundary.upperBound...])
            if content.count < length {
                if complete || error != nil { self.send(self.router.reply(400), to: connection) } else { self.receive(connection, accumulated: bytes) }; return
            }
            let response = self.router.respond(method: first[0], target: first[1], headers: headers, body: Data(content.prefix(length)))
            self.send(response, to: connection)
        }
    }
    private func send(_ response: FixtureRouter.Response, to connection: NWConnection) {
        var fields = ["content-type": "application/json", "cache-control": "no-store"]
        for (name,value) in response.headers { fields[name.lowercased()] = value }
        fields["content-length"] = String(response.body.count); fields["connection"] = "close"
        var headers = "HTTP/1.1 \(response.status) Fixture\r\n"
        for (name,value) in fields.sorted(by: { $0.key < $1.key }) { headers += "\(name): \(value)\r\n" }
        connection.send(content: Data((headers+"\r\n").utf8)+response.body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

#if canImport(XCTest)
import XCTest
private final class FixtureResourceBundle {}
extension FixtureHTTPServer {
    /// Per-test namespace UUIDs keep state isolated even when XCTest reuses the runner process.
    static let shared: FixtureHTTPServer = {
        let bundle = Bundle(for: FixtureResourceBundle.self)
        guard let url = bundle.url(forResource: "retained-ui", withExtension: "json", subdirectory: "FixtureResources"),
              let recordedURL = bundle.url(forResource: "Fixtures", withExtension: nil) else { fatalError("Missing native fixture resources") }
        do { return try FixtureHTTPServer(router: FixtureRouter(resourceURL: url, recordedURL: recordedURL)) }
        catch { fatalError("Native fixture listener failed: \(error)") }
    }()
}
#endif
