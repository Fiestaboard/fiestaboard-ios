import XCTest
@testable import FiestaBoardKit

@MainActor final class ComposePrincipalProofTests: XCTestCase {
    private let deployment = try! DeploymentURL("https://board.test/prefix")
    private func service(_ vault: MemorySessionVault, deployment: DeploymentURL? = nil) -> LiveFiestaBoardService {
        let address = deployment ?? self.deployment
        return LiveFiestaBoardService(deployment:address,transport:URLSessionTransport(deployment:address,
            protocolClasses:[FixtureURLProtocol.self],vault:vault))
    }
    private func installReplies(log: RequestLog = RequestLog(), authenticated: Bool = true, enabled: Bool = true, principal: String = "contract_admin") {
        FixtureURLProtocol.handler = { request in
            log.append(request)
            switch request.url!.lastPathComponent {
            case "health": return (200,[:],try BootstrapTests.body("health"))
            case "discover": return (200,[:],try BootstrapTests.body("discover_disabled"))
            case "login": return (200,[:],MobileFixture.reply("compose-principal"))
            case "session": return (200,[:],Data(#"{"status":"ok"}"#.utf8))
            case "status":
                var value = try JSONSerialization.jsonObject(with:BootstrapTests.body("auth_authenticated")) as! [String:Any]
                let hasBearer = request.value(forHTTPHeaderField:"Authorization") != nil
                value["enabled"] = enabled; value["mode"] = enabled ? "enabled" : "disabled"
                value["authenticated"] = enabled && authenticated && hasBearer
                value["username"] = principal // An unauthenticated name alone grants nothing.
                value["auth_kind"] = authenticated && hasBearer ? "mobile" as Any : NSNull()
                return (200,[:],try JSONSerialization.data(withJSONObject:value))
            default: throw URLError(.badURL)
            }
        }
    }
    private func signIn(_ service: LiveFiestaBoardService, remember: Bool) async throws {
        _ = try await service.bootstrap()
        _ = try await service.login(username:"contract_admin",password:"fixture-password",rememberMe:remember)
    }
    func testProtectedVerifiedPrincipalRestoresOnlyNonsecretOfflineIdentityWithoutNetwork() async throws {
        let vault = MemorySessionVault(), first = service(vault)
        installReplies(); try await signIn(first,remember:true)
        let observed1 = await first.composePrincipal()
        let current = try XCTUnwrap(observed1)
        XCTAssertEqual(current.identity.deploymentID,deployment.description)
        XCTAssertEqual(current.identity.installationID,"id-1")
        XCTAssertEqual(current.identity.principalID,"contract_admin")
        XCTAssertTrue(current.verifiedOnline)
        let fresh = service(vault), log = RequestLog()
        FixtureURLProtocol.handler = { request in log.append(request); throw URLError(.notConnectedToInternet) }
        let observed2 = await fresh.rememberedComposePrincipal(installationID:"id-1")
        let offline = try XCTUnwrap(observed2)
        XCTAssertEqual(offline.identity,current.identity); XCTAssertEqual(offline.connectionID,current.connectionID)
        XCTAssertFalse(offline.verifiedOnline); XCTAssertTrue(log.requests.isEmpty,"Identity lookup must not restore a bearer or send a request")
        let observed3 = await fresh.composePrincipal()
        XCTAssertNil(observed3,"Offline proof cannot publish live authenticated authority")
        let publicBytes = try JSONEncoder().encode(offline.identity)
        let publicString = String(decoding:publicBytes,as:UTF8.self)
        XCTAssertFalse(publicString.contains("fb_mob_")); XCTAssertFalse(publicString.contains("fixture-password"))
        XCTAssertFalse(publicString.contains("sessionID"))
    }
    func testUnrememberedIdentityIsUsableOnlyAfterActualAuthentication() async throws {
        let vault = MemorySessionVault(), first = service(vault)
        installReplies(); try await signIn(first,remember:false)
        let observed4 = await first.composePrincipal()
        XCTAssertNotNil(observed4)
        let observed5 = await service(vault).rememberedComposePrincipal(installationID:"id-1")
        XCTAssertNil(observed5)
        let observed6 = try await vault.load(for:deployment)
        XCTAssertNil(observed6)
    }
    func testLegacyCredentialWithoutPrincipalWaitsForFreshAuthenticatedReadback() async throws {
        let vault = MemorySessionVault()
        let transport = URLSessionTransport(deployment:deployment,protocolClasses:[FixtureURLProtocol.self],vault:vault)
        installReplies()
        await transport.configureSessionPersistence(rememberMe:true,installationID:"id-1")
        _ = try await transport.send(APIRequest(.post,path:["auth","device","login"]))
        let observed7 = try await vault.load(for:deployment)
        let saved = try XCTUnwrap(observed7)
        var legacy = try JSONSerialization.jsonObject(with:saved) as! [String:Any]
        legacy["version"] = 3; legacy.removeValue(forKey:"principalID")
        try await vault.save(JSONSerialization.data(withJSONObject:legacy),for:deployment)
        let fresh = service(vault)
        let observed8 = await fresh.rememberedComposePrincipal(installationID:"id-1")
        XCTAssertNil(observed8)
        let observed9 = try await fresh.restoreRememberedSession(observedInstallationID:"id-1")
        XCTAssertTrue(observed9)
        let observed10 = await fresh.composePrincipal()?.identity.principalID
        XCTAssertEqual(observed10,"contract_admin")
        let observed11 = await service(vault).rememberedComposePrincipal(installationID:"id-1")
        XCTAssertNotNil(observed11)
    }
    func testDeploymentAndInstallationMismatchCannotSelectAnotherBuffer() async throws {
        let vault = MemorySessionVault(), first = service(vault)
        installReplies(); try await signIn(first,remember:true)
        let observed12 = try await vault.load(for:deployment)
        let saved = try XCTUnwrap(observed12)
        let observed13 = await service(vault).rememberedComposePrincipal(installationID:"another-installation")
        XCTAssertNil(observed13)
        for url in ["https://other.test/prefix","https://board.test/other","https://board.test:8443/prefix"] {
            let wrong = try DeploymentURL(url)
            try await vault.save(saved,for:wrong)
            let observed14 = await service(vault,deployment:wrong).rememberedComposePrincipal(installationID:"id-1")
            XCTAssertNil(observed14)
        }
    }
    func testUnauthenticatedUsernameAndDisabledAuthenticationNeverInventPrincipal() async throws {
        for enabled in [false,true] {
            let vault = MemorySessionVault(), first = service(vault)
            installReplies(authenticated:false,enabled:enabled)
            _ = try await first.bootstrap()
            let current = await first.composePrincipal()
            let offline = await first.rememberedComposePrincipal(installationID:"id-1")
            XCTAssertNil(current); XCTAssertNil(offline)
        }
    }
    func testPrincipalBytesAreNotNormalizedAcrossProtectedRestore() async throws {
        let principal = "cafe\u{0301}", vault = MemorySessionVault(), first = service(vault)
        installReplies(principal:principal)
        _ = try await first.bootstrap()
        _ = try await first.login(username:principal,password:"fixture-password",rememberMe:true)
        let current = await first.composePrincipal()
        let restored = await service(vault).rememberedComposePrincipal(installationID:"id-1")
        XCTAssertEqual(current.map { Data($0.identity.principalID.utf8) },Data(principal.utf8))
        XCTAssertEqual(restored.map { Data($0.identity.principalID.utf8) },Data(principal.utf8))
        XCTAssertNotEqual(restored.map { Data($0.identity.principalID.utf8) },Data("caf\u{00e9}".utf8))
    }
    func testMalformedExpiredAndMissingProtectedPrincipalFailClosed() async throws {
        let vault = MemorySessionVault(), first = service(vault)
        installReplies(); try await signIn(first,remember:true)
        let observed17 = try await vault.load(for:deployment)
        let saved = try XCTUnwrap(observed17)
        let object = try JSONSerialization.jsonObject(with:saved) as! [String:Any]
        var variants: [Data] = [Data("corrupt".utf8)]
        for value in ["", "\0", 123] as [Any] {
            var changed = object; changed["principalID"] = value
            variants.append(try JSONSerialization.data(withJSONObject:changed))
        }
        var missing = object; missing.removeValue(forKey:"principalID")
        variants.append(try JSONSerialization.data(withJSONObject:missing))
        var expired = object, session = object["session"] as! [String:Any]
        session["expiresAt"] = 0; expired["session"] = session
        variants.append(try JSONSerialization.data(withJSONObject:expired))
        for value in variants {
            try await vault.save(value,for:deployment)
            let observed18 = await service(vault).rememberedComposePrincipal(installationID:"id-1")
            XCTAssertNil(observed18)
        }
    }
    func testForgetAndLogoutRevokeRememberedBufferAuthority() async throws {
        for logout in [false,true] {
            let vault = MemorySessionVault(), first = service(vault)
            installReplies(); try await signIn(first,remember:true)
            if logout { try await first.logout() } else { await first.forgetRememberedSession() }
            let observed19 = await service(vault).rememberedComposePrincipal(installationID:"id-1")
            XCTAssertNil(observed19)
            if logout {
                let observed20 = await first.composePrincipal()
                XCTAssertNil(observed20)
            }
        }
    }
    func testSuspendedPrincipalSaveCannotResurrectAuthorityAfterForget() async throws {
        let vault = MemorySessionVault(), first = service(vault)
        installReplies(); try await signIn(first,remember:true)
        await vault.pauseSave()
        let refreshing = Task { try await first.bootstrap() }
        await vault.waitForSave()
        let forget = Task { await first.forgetRememberedSession() }
        while await first.sessionPersistenceState().rememberMe { await Task.yield() }
        await vault.resumeSave(); _ = try? await refreshing.value; await forget.value
        let observed21 = await service(vault).rememberedComposePrincipal(installationID:"id-1")
        XCTAssertNil(observed21)
        let observed22 = try await vault.load(for:deployment)
        XCTAssertNil(observed22)
    }
}
