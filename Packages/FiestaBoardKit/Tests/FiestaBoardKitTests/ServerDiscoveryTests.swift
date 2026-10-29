import Foundation
import Network
import XCTest
@testable import FiestaBoardKit

@MainActor
final class ServerDiscoveryTests: XCTestCase {
    func ad(_ id: String = "one", product: String = "FiestaBoard", path: String = "/", type: String = "_http._tcp") -> BonjourAdvertisement {
        BonjourAdvertisement(id: id, name: "Advertised", serviceType: type, txt: ["product": product, "path": path], endpoint: .hostPort(host: "board.local", port: 4420))
    }
    func identity(_ name: String = "Verified") throws -> ServerIdentity {
        try ServerIdentity(product: "FiestaBoard", version: "10.1.17", installationID: "one", name: name)
    }
    func discovery(_ source: AsyncThrowingStream<[BonjourAdvertisement], Error>, verify: @escaping @Sendable (DeploymentURL) async throws -> ServerIdentity, limit: Int = 3, timeout: Duration = .seconds(1)) -> BonjourServerDiscovery {
        BonjourServerDiscovery(advertisements: { source }, resolve: { advertisement in
            guard case .hostPort(let host, let port) = advertisement.endpoint else { throw URLError(.badURL) }
            return try BonjourServerDiscovery.deployment(host: "\(host)", port: Int(port.rawValue), path: advertisement.txt["path"]!)
        }, verify: verify, verificationTimeout: timeout, maximumConcurrentVerifications: limit)
    }
    func testTXTFiltersUnrelatedServicesAndIdentityVerificationIsRequired() async throws {
        let valid = ad()
        let wrong = ad("wrong", product: "Other")
        let missing = ad("missing", path: "/other")
        let type = ad("type", type: "_other._tcp")
        let source = AsyncThrowingStream<[BonjourAdvertisement], Error> { $0.yield([valid, wrong, missing, type]); $0.finish() }
        let verified = try identity()
        let resolutions = ResolutionLog()
        let browser = BonjourServerDiscovery(advertisements: { source }, resolve: { advertisement in
            await resolutions.append(advertisement.id)
            return try DeploymentURL("http://board.local:4420", allowLocalHTTP: true)
        }, verify: { deployment in
            XCTAssertEqual(deployment.description, "http://board.local:4420")
            return verified
        }, verificationTimeout: .seconds(1), maximumConcurrentVerifications: 3)
        var snapshots: [[DiscoveredServer]] = []
        for try await snapshot in browser.snapshots() { snapshots.append(snapshot) }
        let resolvedIDs = await resolutions.ids
        XCTAssertEqual(resolvedIDs, ["one"])
        XCTAssertEqual(snapshots.last?.count, 1)
        XCTAssertEqual(snapshots.last?.first?.displayName, "Verified")
        let failure = discovery(AsyncThrowingStream { $0.yield([valid]); $0.finish() }, verify: { _ in throw FiestaBoardError.wrongProduct })
        var failed: [DiscoveredServer] = []
        for try await snapshot in failure.snapshots() { failed = snapshot }
        XCTAssertTrue(failed.isEmpty)
    }
    func testDuplicateDeploymentsAreUniqueAndRemovalClearsCurrentSnapshot() async throws {
        let (source, feed) = AsyncThrowingStream<[BonjourAdvertisement], Error>.makeStream()
        let verified = try identity()
        let browser = discovery(source, verify: { _ in verified })
        var iterator = browser.snapshots().makeAsyncIterator()
        _ = try await iterator.next()
        feed.yield([ad(), ad("duplicate")])
        var found: [DiscoveredServer] = []
        while found.isEmpty { found = try await iterator.next() ?? [] }
        XCTAssertEqual(found.count, 1)
        feed.yield([])
        while let snapshot = try await iterator.next() {
            if snapshot.isEmpty { break }
        }
        feed.finish()
        let end = try await iterator.next()
        XCTAssertNil(end)
    }
    func testRemovedSlowVerificationCannotReappearAndPendingWorkCancels() async throws {
        let (source, feed) = AsyncThrowingStream<[BonjourAdvertisement], Error>.makeStream()
        let gate = VerificationGate()
        let verified = try identity()
        let browser = discovery(source, verify: { _ in try await gate.pause(); return verified })
        let consumer = Task { () throws -> [[DiscoveredServer]] in
            var values: [[DiscoveredServer]] = []
            for try await value in browser.snapshots() { values.append(value) }
            return values
        }
        feed.yield([ad()])
        await gate.waitForStart()
        feed.yield([])
        feed.finish()
        let values = try await consumer.value
        XCTAssertTrue(values.allSatisfy(\.isEmpty))
        await gate.waitForCancellation()
        let cancelled = await gate.cancelled
        XCTAssertTrue(cancelled)
    }
    func testTimeoutAndConcurrencyAreBoundedAndConsumerCancellationStopsSource() async throws {
        let (source, feed) = AsyncThrowingStream<[BonjourAdvertisement], Error>.makeStream()
        let terminated = expectation(description: "source terminated")
        feed.onTermination = { _ in terminated.fulfill() }
        let gate = VerificationGate()
        let verified = try identity()
        let browser = discovery(source, verify: { _ in try await gate.pause(); return verified }, limit: 2, timeout: .milliseconds(30))
        let consumer = Task { for try await _ in browser.snapshots() {} }
        feed.yield((0..<8).map { ad("\($0)") })
        await gate.waitForStart()
        try await Task.sleep(for: .milliseconds(150))
        let maximum = await gate.maximum
        XCTAssertEqual(maximum, 2)
        consumer.cancel()
        _ = await consumer.result
        await fulfillment(of: [terminated], timeout: 1)
    }
    func testEmptyBrowseAndAmbiguousFailureRemainTruthful() async throws {
        let verified = try identity()
        let empty = discovery(AsyncThrowingStream { $0.finish() }, verify: { _ in verified })
        var values: [[DiscoveredServer]] = []
        for try await value in empty.snapshots() { values.append(value) }
        XCTAssertEqual(values, [[]])
        let failed = discovery(AsyncThrowingStream { $0.finish(throwing: ServerDiscoveryError.unavailable) }, verify: { _ in verified })
        do { for try await _ in failed.snapshots() {}; XCTFail("Expected browse error") }
        catch { XCTAssertEqual(error as? ServerDiscoveryError, .unavailable) }
        XCTAssertFalse(ServerDiscoveryError.unavailable.localizedDescription.lowercased().contains("denied"))
    }
    func testAnonymousVerificationUsesOnlyPublicDiscoverAndDoesNotCarryCookiesOrCredentials() async throws {
        let log = RequestLog()
        FixtureURLProtocol.handler = { request in
            log.append(request)
            return (200, ["Set-Cookie": "session=fixture-cookie; Path=/"], Data(#"{"product":"FiestaBoard","version":"10.1.17","id":"one","name":"Verified"}"#.utf8))
        }
        let deployment = try DeploymentURL("https://board.test/proxy")
        for _ in 0..<2 {
            let result = try await AnonymousDiscoveryVerifier.verify(deployment, protocolClasses: [FixtureURLProtocol.self])
            XCTAssertEqual(result.installationID, "one")
        }
        XCTAssertEqual(log.requests.map { $0.url!.path }, ["/proxy/api/discover", "/proxy/api/discover"])
        for request in log.requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        }
    }
    func testAnonymousVerificationRejectsRedirectStatusOversizedBodyAndWrongProduct() async throws {
        for (status, body) in [(302, "{}"), (200, String(repeating: "x", count: 65_537)),
                                (200, #"{"product":"Other","version":"1","id":"one","name":"Other"}"#)] {
            FixtureURLProtocol.handler = { _ in (status, ["Location": "https://other.test/api/discover"], Data(body.utf8)) }
            do {
                _ = try await AnonymousDiscoveryVerifier.verify(try DeploymentURL("https://board.test"), protocolClasses: [FixtureURLProtocol.self])
                XCTFail("Expected identity rejection")
            } catch { XCTAssertTrue(error is ServerDiscoveryError || error as? FiestaBoardError == .wrongProduct) }
        }
    }
    func testResolvedIPv6PortsAndUnsafePaths() throws {
        XCTAssertEqual(try BonjourServerDiscovery.deployment(host: "fiestapi.local.", port: 4420, path: "/").description, "http://fiestapi.local:4420")
        XCTAssertEqual(try BonjourServerDiscovery.deployment(host: "fd00::1", port: 4420, path: "/").description, "http://[fd00::1]:4420")
        XCTAssertEqual(try BonjourServerDiscovery.deployment(host: "192.168.1.8", port: 8080, path: "/").description, "http://192.168.1.8:8080")
        XCTAssertThrowsError(try BonjourServerDiscovery.deployment(host: "example.com", port: 80, path: "/"))
        XCTAssertThrowsError(try BonjourServerDiscovery.deployment(host: "board.local", port: 0, path: "/"))
        XCTAssertThrowsError(try BonjourServerDiscovery.deployment(host: "board.local", port: 80, path: "/../"))
    }
}

private actor VerificationGate {
    private var starts = 0
    private var active = 0
    private var waiter: CheckedContinuation<Void, Never>?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?
    private(set) var maximum = 0
    private(set) var cancelled = false
    func pause() async throws {
        starts += 1; active += 1; maximum = max(maximum, active)
        waiter?.resume(); waiter = nil
        defer { active -= 1 }
        do { try await Task.sleep(for: .seconds(30)) }
        catch { cancelled = true; cancellationWaiter?.resume(); cancellationWaiter = nil; throw error }
    }
    func waitForCancellation() async {
        if cancelled { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }
    func waitForStart() async {
        if starts > 0 { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

private actor ResolutionLog {
    private(set) var ids: [String] = []
    func append(_ id: String) { ids.append(id) }
}
