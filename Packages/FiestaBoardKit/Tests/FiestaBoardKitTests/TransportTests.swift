import XCTest
@testable import FiestaBoardKit
import Foundation

final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var received = request
            if received.httpBody == nil, let stream = received.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var body = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
                received.httpBody = body
            }
            let (status, headers, data) = try Self.handler!(received)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [URLRequest] = []
    func append(_ r: URLRequest) { lock.withLock { entries.append(r) } }
    var requests: [URLRequest] { lock.withLock { entries } }
}

@MainActor
final class TransportTests: XCTestCase {
    func transport(_ url: String = "https://board.test/prefix") throws -> URLSessionTransport {
        URLSessionTransport(deployment: try DeploymentURL(url), protocolClasses: [FixtureURLProtocol.self])
    }
    func testHTTPAuthenticationConflictsThrottleAndPartialWritesStayDistinct() async throws {
        let cases: [(Int, String, FiestaBoardError)] = [
            (401, #"{"detail":"password=secret"}"#, .unauthenticated),
            (409, "{}", .conflict), (412, "{}", .pageConflict), (429, "{}", .rateLimited(retryAfterSeconds: 7)),
            (502, #"{"detail":{"message":"secret","partial":true,"failed_regions":[{"row":0,"col":3,"rows":2,"cols":3}]}}"#,
             .partialWrite(failedRegions: [try JSONDecoder().decode(FailedRegion.self, from: Data(#"{"row":0,"col":3,"rows":2,"cols":3}"#.utf8))]))
        ]
        for (status, body, expected) in cases {
            FixtureURLProtocol.handler = { _ in (status, ["Retry-After": "7"], Data(body.utf8)) }
            do { _ = try await transport().send(APIRequest(.post, path: ["v1", "boards", "b2", "message"]))
                XCTFail("Expected HTTP \(status)")
            } catch {
                XCTAssertEqual(error as? FiestaBoardError, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }
    func testUncertainMutationIsNotRetriedAndReadFailureIsSafe() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); throw URLError(.networkConnectionLost) }
        let transport = try transport()
        do { _ = try await transport.send(APIRequest(.post, path: ["v1", "boards", "b2", "message"])) }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        XCTAssertEqual(log.requests.count, 1)
        do { _ = try await transport.send(APIRequest(path: ["v1", "boards"])) }
        catch { XCTAssertEqual(error as? FiestaBoardError, .networkUnavailable) }
        XCTAssertEqual(log.requests.count, 2)
    }
    func testRedirectIsRefusedAnd202IsPreserved() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { r in log.append(r); return (302, ["Location": "https://evil.test"], Data()) }
        do { _ = try await transport().send(APIRequest(path: ["auth", "status"])) }
        catch { XCTAssertEqual(error as? FiestaBoardError, .redirectRefused) }
        XCTAssertEqual(log.requests.count, 1)
        FixtureURLProtocol.handler = { _ in (202, [:], Data("{}".utf8)) }
        let response = try await transport().send(APIRequest(.post, path: ["v1", "boards", "b2", "message"]))
        XCTAssertEqual(response.status, 202)
    }
    func testMobileTokenDoesNotCrossDeploymentPrefixPortOrFreshContext() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { r in
            log.append(r)
            return (200, [:], r.url!.path.hasSuffix("login") ? MobileFixture.reply("private") : Data("{}".utf8))
        }
        let a = try transport()
        _ = try await a.send(APIRequest(.post, path: ["auth", "device", "login"]))
        _ = try await a.send(APIRequest(path: ["auth", "status"]))
        _ = try await transport("https://board.test/other").send(APIRequest(path: ["auth", "status"]))
        _ = try await transport("https://board.test:8443/prefix").send(APIRequest(path: ["auth", "status"]))
        _ = try await transport().send(APIRequest(path: ["auth", "status"]))
        await a.resetSession()
        _ = try await a.send(APIRequest(path: ["auth", "status"]))
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fb_mob_private")
        for index in [0, 2, 3, 4, 5] { XCTAssertNil(log.requests[index].value(forHTTPHeaderField: "Authorization")) }
        XCTAssertEqual(log.requests[0].url!.path, "/prefix/api/auth/device/login")
    }
    func testBrowserCookieHeadersAreAlwaysIgnored() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            return (200, ["Set-Cookie":"fiestaboard_session=browser; Path=/; Secure"], Data("{}".utf8))
        }
        let t = try transport()
        _ = try await t.send(APIRequest(path: ["auth", "status"]))
        _ = try await t.send(APIRequest(path: ["boards"]))
        XCTAssertTrue(log.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

}

final class DeferredTransportResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: DeferredTransportURLProtocol?
    private var capturedAuthorizations: [String?] = []
    var authorizations: [String?] { lock.withLock { capturedAuthorizations } }
    private var waiter: CheckedContinuation<Void, Never>?
    func capture(_ value: DeferredTransportURLProtocol) {
        let waiting = lock.withLock { capturedAuthorizations.append(value.request.value(forHTTPHeaderField: "Authorization")); pending = value; let w = waiter; waiter = nil; return w }
        waiting?.resume()
    }
    func waitUntilPending() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { if pending != nil { return true }; waiter = continuation; return false }
            if ready { continuation.resume() }
        }
    }
    func release() {
        let request = lock.withLock { let p = pending; pending = nil; return p }
        request?.respond(headers: ["Set-Cookie":"fiestaboard_session=stale; Path=/; Secure"])
    }
}
final class DeferredTransportURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var coordinator: DeferredTransportResponse!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.coordinator.capture(self) }
    override func stopLoading() {}
    func respond(headers: [String: String]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
extension TransportTests {
    func testSessionResetRejectsLateResponseBeforeInstallingItsCredential() async throws {
        let coordinator = DeferredTransportResponse()
        DeferredTransportURLProtocol.coordinator = coordinator
        let transport = URLSessionTransport(deployment: try DeploymentURL("https://board.test/prefix"), protocolClasses: [DeferredTransportURLProtocol.self])
        let oldLogin = Task { try await transport.send(APIRequest(.post, path: ["auth", "device", "login"])) }
        await coordinator.waitUntilPending()
        await transport.resetSession()
        coordinator.release()
        do { _ = try await oldLogin.value; XCTFail("Expected stale response rejection") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        let status = Task { try await transport.send(APIRequest(path: ["auth", "status"])) }
        await coordinator.waitUntilPending()
        XCTAssertNil(coordinator.authorizations.last ?? nil)
        coordinator.release()
        _ = try await status.value
    }
}


extension TransportTests {
    func testMutationRedirectCannotPromiseNoSideEffectOrReplay() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (307, ["Location":"https://evil.test"], Data()) }
        do {
            _ = try await transport().send(APIRequest(.put, path:["v1", "boards", "b2", "active-page"]))
            XCTFail("Expected uncertain mutation result")
        } catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        XCTAssertEqual(log.requests.count, 1)
    }
}

extension TransportTests {
    func testBoundedHeadersPreserveExactOriginAndNeverCarryProofToOtherEndpoints() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, [:], Data("{}".utf8)) }
        let transport = try transport()
        _ = try await transport.send(APIRequest(.post, path: ["auth", "setup"], context: .onboardingToken("setup-proof"), cachePolicy: .noStore))
        _ = try await transport.send(APIRequest(.post, path: ["auth", "sessions", "revoke"], context: .browserSession(origin: "https://external.test:8443", csrfToken: "fresh-proof")))
        _ = try await transport.send(APIRequest(path: ["auth", "status"]))
        XCTAssertEqual(log.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer setup-proof")
        XCTAssertEqual(log.requests[0].value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField: "Origin"), "https://external.test:8443")
        XCTAssertEqual(log.requests[1].value(forHTTPHeaderField: "X-CSRF-Token"), "fresh-proof")
        XCTAssertNil(log.requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(log.requests[2].value(forHTTPHeaderField: "Authorization"))
        let bad: [APIRequest] = [
            APIRequest(.post, path: ["auth", "sessions"], context: .onboardingToken("proof")),
            APIRequest(.post, path: ["auth", "preference"], body: Data(#"{"enabled":false}"#.utf8), context: .onboardingToken("proof")),
            APIRequest(.post, path: ["auth", "setup"], context: .onboardingToken("secret\r\nCookie: x")),
            APIRequest(.post, path: ["auth", "sessions"], context: .browserSession(origin: "https://external.test/path", csrfToken: "proof")),
            APIRequest(.post, path: ["auth", "sessions"], context: .browserSession(origin: "https://external.test", csrfToken: "proof\n"))
        ]
        for request in bad {
            do { _ = try await transport.send(request); XCTFail("Expected context refusal") }
            catch { XCTAssertEqual(error as? FiestaBoardError, .invalidRequestContext) }
        }
        XCTAssertEqual(log.requests.count, 3)
    }
    func testOnboardingAndSafeValidationErrorsAreTypedWithoutRawSecrets() async throws {
        let cases: [(Int, [String], String, FiestaBoardError)] = [
            (401, ["auth", "device", "login"], #"{"detail":"Invalid username or password"}"#, .invalidCredentials),
            (409, ["v1", "boards"], #"{"detail":"Setup required","setup_required":true,"first_run":true}"#, .setupRequired(firstRun: true)),
            (409, ["auth", "setup"], #"{"detail":"Already set up"}"#, .onboardingConflict(.alreadySetUp)),
            (409, ["auth", "preference"], #"{"detail":"Auth mode is pinned by FIESTABOARD_AUTH_ENABLED."}"#, .onboardingConflict(.modePinned)),
            (403, ["auth", "setup"], #"{"detail":"This install has a stored MCP token. Present it as a Bearer token to enable login, or clear the token first."}"#, .setupProofRequired),
            (403, ["auth", "sessions"], #"{"error":"forbidden","detail":"Refresh this page and try again."}"#, .csrfRequired),
            (403, ["auth", "setup"], #"{"detail":"secret arbitrary error"}"#, .forbidden),
            (422, ["auth", "setup"], #"{"detail":[{"loc":["body","password"],"type":"string_too_short","input":"secret","msg":"secret"},{"loc":["body","secret"],"type":"secret"}]}"#, .validation(fields: [.password])),
            (503, ["health"], #"{"detail":"secret startup internals"}"#, .startupUnavailable),
            (503, ["health"], "<html>secret proxy page</html>", .gatewayUnavailable)
        ]
        for (status, path, body, expected) in cases {
            FixtureURLProtocol.handler = { _ in (status, [:], Data(body.utf8)) }
            do { _ = try await transport().send(APIRequest(path == ["health"] || path == ["v1", "boards"] ? .get : .post, path: path)); XCTFail("Expected error") }
            catch {
                XCTAssertEqual(error as? FiestaBoardError, expected)
                XCTAssertFalse(String(describing: error).contains("secret"))
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }
}

extension TransportTests {
    func testHTMLNeverHidesAuthenticationLossOrRedirectRefusal() async throws {
        for (status, expected) in [(401, FiestaBoardError.unauthenticated), (302, .redirectRefused)] {
            FixtureURLProtocol.handler = { _ in (status, ["Content-Type": "text/html"], Data("<html>private gateway detail</html>".utf8)) }
            do { _ = try await transport().send(APIRequest(path: ["auth", "status"])); XCTFail("Expected HTTP refusal") }
            catch { XCTAssertEqual(error as? FiestaBoardError, expected) }
        }
    }
    func testGatewayReadAndMutationRemainDistinctWithoutReplay() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); return (200, ["Content-Type": "text/html"], Data("<html>private</html>".utf8)) }
        let transport = try transport()
        do { _ = try await transport.send(APIRequest(path: ["health"])); XCTFail("Expected gateway") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .gatewayUnavailable) }
        do { _ = try await transport.send(APIRequest(.post, path: ["auth", "setup"])); XCTFail("Expected unknown mutation") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .unknownMutationOutcome) }
        XCTAssertEqual(log.requests.count, 2)
    }
}

/// Only the logout reply is suspended; login/status still exercise the real bearer transport.
private final class NativeAuthenticationCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: NativeAuthenticationURLProtocol?
    private var waiter: CheckedContinuation<Void, Never>?
    private var recorded: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { recorded } }
    func receive(_ value: NativeAuthenticationURLProtocol) {
        let request = value.request
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            recorded.append(request)
            if request.url!.lastPathComponent == "session" {
                pending = value; let result = waiter; waiter = nil; return result
            }
            return nil
        }
        if request.url!.lastPathComponent == "session" { waiting?.resume(); return }
        if request.url!.lastPathComponent == "login" {
            value.respond(status: 200, headers: [:], data: MobileFixture.reply("replacement"))
        } else {
            value.respond(status: 200, headers: [:], data: fixture("auth"))
        }
    }
    func waitForLogout() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { if pending != nil { return true }; waiter = continuation; return false }
            if ready { continuation.resume() }
        }
    }
    func releaseLogout() {
        let value = lock.withLock { let result = pending; pending = nil; return result }
        value?.respond(status: 200, headers: ["Set-Cookie": "fiestaboard_session=; Path=/; Max-Age=0"], data: Data(#"{"status":"ok"}"#.utf8))
    }
}
private final class NativeAuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var coordinator: NativeAuthenticationCoordinator!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.coordinator.receive(self) }
    override func stopLoading() {}
    func respond(status: Int, headers: [String: String], data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
extension TransportTests {
    func testOldLogoutCannotDeleteReplacementMobileCredential() async throws {
        let coordinator = NativeAuthenticationCoordinator()
        NativeAuthenticationURLProtocol.coordinator = coordinator
        let deployment = try DeploymentURL("https://board.test/prefix")
        let service = LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [NativeAuthenticationURLProtocol.self]))
        let oldLogout = Task { try await service.logout() }
        await coordinator.waitForLogout()
        let status = try await service.login(username: "demo", password: "fixture-password")
        XCTAssertEqual(status.bootstrapPhase, .ready)
        XCTAssertEqual(coordinator.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fb_mob_replacement")
        coordinator.releaseLogout()
        do { try await oldLogout.value; XCTFail("Expected obsolete logout") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        _ = try await service.authStatus()
        XCTAssertEqual(coordinator.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer fb_mob_replacement")
        XCTAssertEqual(coordinator.requests.filter { $0.url!.lastPathComponent == "login" }.count, 1)
    }
}
