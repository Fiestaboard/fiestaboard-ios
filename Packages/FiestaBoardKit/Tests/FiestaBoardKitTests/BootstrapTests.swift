import XCTest
@testable import FiestaBoardKit

@MainActor
final class BootstrapTests: XCTestCase {
    let deployment = try! DeploymentURL("https://board.test/prefix")
    func service(auth: String = "auth_disabled", log: RequestLog = RequestLog(), product: String? = nil) -> LiveFiestaBoardService {
        FixtureURLProtocol.handler = { request in
            log.append(request)
            let name: String
            switch request.url!.lastPathComponent {
            case "health": name = "health"
            case "discover": name = "discover_disabled"
            case "status": name = auth
            default: throw URLError(.badURL)
            }
            var value = try Self.body(name)
            if let product, name.hasPrefix("discover") {
                var object = try JSONSerialization.jsonObject(with: value) as! [String: Any]
                object["product"] = product
                value = try JSONSerialization.data(withJSONObject: object)
            }
            return (200, [:], value)
        }
        return LiveFiestaBoardService(deployment: deployment, transport: URLSessionTransport(deployment: deployment, protocolClasses: [FixtureURLProtocol.self]))
    }
    nonisolated static func body(_ name: String) throws -> Data {
        let root = try JSONSerialization.jsonObject(with: fixture("bootstrap-control")) as! [String: Any]
        let cases = root["cases"] as! [[String: Any]]
        let value = cases.first { $0["id"] as? String == name }!["response"] as! [String: Any]
        return try JSONSerialization.data(withJSONObject: value["body"]!)
    }
    func testPublicBootstrapNeedsNoBoardsVersionOrLibraryAndAcceptsStoppedService() async throws {
        let log = RequestLog()
        let snapshot = try await service(log: log).bootstrap()
        XCTAssertEqual(snapshot.deployment, deployment)
        XCTAssertEqual(snapshot.identity.product, "FiestaBoard")
        XCTAssertEqual(snapshot.identity.installationID, "id-1")
        XCTAssertFalse(snapshot.health.serviceRunning)
        XCTAssertEqual(snapshot.phase, .ready)
        XCTAssertEqual(log.requests.map { $0.url!.path }, ["/prefix/api/health", "/prefix/api/discover", "/prefix/api/auth/status"])
        XCTAssertTrue(log.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cache-Control") == "no-store" })
    }
    func testAuthPhasesAndOptionalCapabilitiesPreserveCurrentAndLegacyReplies() async throws {
        for (name, phase) in [("auth_undecided", BootstrapPhase.chooseAuthentication), ("auth_enabled", .setupAdministrator), ("auth_disabled", .ready), ("auth_authenticated", .ready)] {
            let value = try await service(auth: name).bootstrap()
            XCTAssertEqual(value.phase, phase)
            XCTAssertEqual(value.auth.sessionManagementSupported, true)
            XCTAssertEqual(value.auth.tvSignIn?.protocolVersion, 1)
        }
        let legacy = try JSONDecoder().decode(AuthStatus.self, from: Data(#"{"enabled":true,"setup_required":false,"authenticated":true,"username":"demo"}"#.utf8))
        XCTAssertNil(legacy.sessionManagementSupported)
        let tv = try JSONDecoder().decode(AuthStatus.self, from: Data(#"{"enabled":true,"authenticated":true,"setup_required":false,"auth_kind":"tv"}"#.utf8))
        XCTAssertEqual(tv.bootstrapPhase, .signIn)
        let loggedOut = try JSONDecoder().decode(AuthStatus.self, from: Data(#"{"enabled":true,"authenticated":false,"setup_required":false}"#.utf8))
        XCTAssertEqual(loggedOut.bootstrapPhase, .signIn)
    }
    func testWrongProductCannotBecomeConnected() async throws {
        do { _ = try await service(product: "Other").bootstrap(); XCTFail("Expected product rejection") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .wrongProduct) }
    }
    func testDemoBootstrapHasExplicitReadyIdentity() async throws {
        let value = try await FixtureFiestaBoardService().bootstrap()
        XCTAssertEqual(value.phase, .ready)
        XCTAssertEqual(value.identity.installationID, "demo")
    }
}

extension BootstrapTests {
    func testIdentityInitializerRejectsWrongProductButAllowsUnconfiguredIDAndName() throws {
        XCTAssertThrowsError(try ServerIdentity(product: "Other", version: "10.1.17", installationID: "", name: "")) {
            XCTAssertEqual($0 as? FiestaBoardError, .wrongProduct)
        }
        XCTAssertEqual(try ServerIdentity(product: "FiestaBoard", version: "10.1.17", installationID: "", name: "").name, "")
    }
    func testSlowBootstrapCannotSurviveSessionChange() async throws {
        let transport = BootstrapPauseTransport()
        let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
        let pending = Task { try await service.bootstrap() }
        await transport.waitForHealth()
        try await service.logout()
        await transport.releaseHealth()
        do { _ = try await pending.value; XCTFail("Expected stale bootstrap") }
        catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
        let paths = await transport.paths
        XCTAssertFalse(paths.contains(["discover"]))
    }
    func testCancelledBootstrapDoesNotContinueToDiscovery() async throws {
        let transport = BootstrapPauseTransport()
        let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
        let pending = Task { try await service.bootstrap() }
        await transport.waitForHealth()
        pending.cancel()
        await transport.releaseHealth()
        do { _ = try await pending.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let paths = await transport.paths
        XCTAssertFalse(paths.contains(["discover"]))
    }
}

private actor BootstrapPauseTransport: APITransport {
    private var health: CheckedContinuation<APIResponse, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var paths: [[String]] = []
    func resetSession() {}
    func send(_ request: APIRequest) async throws -> APIResponse {
        paths.append(request.path)
        if request.path == ["health"] {
            return await withCheckedContinuation { continuation in
                health = continuation; waiter?.resume(); waiter = nil
            }
        }
        if request.path == ["auth", "logout"] { return APIResponse(status: 200, data: Data(#"{"status":"ok"}"#.utf8)) }
        throw FiestaBoardError.invalidPath
    }
    func waitForHealth() async {
        if health != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func releaseHealth() {
        health?.resume(returning: APIResponse(status: 200, data: Data(#"{"status":"ok","service_running":false,"version":"10.1.17"}"#.utf8)))
        health = nil
    }
}

extension BootstrapTests {
    func testOldBootstrapAndAuthStatusCannotOutliveSetupOrDisablePreference() async throws {
        for bootstrapRead in [true, false] {
            for setup in [true, false] {
                let transport = OnboardingTransitionTransport(setup: setup)
                let service = LiveFiestaBoardService(deployment: deployment, transport: transport)
                let oldPhase = Task { () throws -> BootstrapPhase in
                    if bootstrapRead { return try await service.bootstrap().phase }
                    return try await service.authStatus().bootstrapPhase
                }
                await transport.waitForOldStatus()
                let newStatus: AuthStatus
                if setup { newStatus = try await service.setupAdministrator(username: "contract_admin", password: "fixture-password") }
                else { newStatus = try await service.setAuthenticationPreference(enabled: false) }
                XCTAssertEqual(newStatus.bootstrapPhase, .ready)
                try await transport.releaseOldStatus()
                do {
                    let obsolete = try await oldPhase.value
                    XCTFail("Old \(bootstrapRead ? "bootstrap" : "authStatus") returned \(obsolete) after \(setup ? "setup" : "disable preference")")
                } catch { XCTAssertEqual(error as? FiestaBoardError, .staleSession) }
                let currentStatus = try await service.authStatus()
                XCTAssertEqual(currentStatus.bootstrapPhase, .ready)
                let paths = await transport.paths
                XCTAssertEqual(paths.filter { $0 == ["auth", setup ? "setup" : "preference"] }.count, 1)
            }
        }
    }
}

private actor OnboardingTransitionTransport: APITransport {
    let setup: Bool
    private var statusCount = 0
    private var oldStatus: CheckedContinuation<APIResponse, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var paths: [[String]] = []
    init(setup: Bool) { self.setup = setup }
    func resetSession() {}
    func send(_ request: APIRequest) async throws -> APIResponse {
        paths.append(request.path)
        if request.path == ["health"] { return APIResponse(status: 200, data: try BootstrapTests.body("health")) }
        if request.path == ["discover"] { return APIResponse(status: 200, data: try BootstrapTests.body("discover_disabled")) }
        if request.path == ["auth", "status"] {
            statusCount += 1
            if statusCount == 1 {
                return await withCheckedContinuation { continuation in
                    oldStatus = continuation; waiter?.resume(); waiter = nil
                }
            }
            return APIResponse(status: 200, data: try BootstrapTests.body(setup ? "auth_authenticated" : "auth_disabled"))
        }
        if request.path == ["auth", "setup"] || request.path == ["auth", "preference"] {
            return APIResponse(status: setup ? 201 : 200, data: Data(#"{"status":"ok"}"#.utf8))
        }
        throw FiestaBoardError.invalidPath
    }
    func waitForOldStatus() async {
        if oldStatus == nil { await withCheckedContinuation { waiter = $0 } }
    }
    func releaseOldStatus() throws {
        oldStatus?.resume(returning: APIResponse(status: 200, data: try BootstrapTests.body(setup ? "auth_enabled" : "auth_undecided")))
        oldStatus = nil
    }
}
