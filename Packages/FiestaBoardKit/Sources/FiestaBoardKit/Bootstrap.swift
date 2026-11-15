import Foundation

public enum BootstrapPhase: Sendable, Equatable { case chooseAuthentication, setupAdministrator, signIn, ready }

public struct TVSignInStatus: Codable, Sendable, Equatable {
    public let supported: Bool
    public let enabled: Bool
    public let protocolVersion: Int
    public init(supported: Bool, enabled: Bool, protocolVersion: Int) {
        self.supported = supported; self.enabled = enabled; self.protocolVersion = protocolVersion
    }
    enum CodingKeys: String, CodingKey { case supported, enabled; case protocolVersion = "protocol_version" }
}
public struct ServerIdentity: Codable, Sendable, Equatable {
    public let product: String
    public let version: String
    public let installationID: String
    public let name: String
    public init(product: String, version: String, installationID: String, name: String) throws {
        guard product == "FiestaBoard" else { throw FiestaBoardError.wrongProduct }
        self.product = product; self.version = version; self.installationID = installationID; self.name = name
    }
    enum CodingKeys: String, CodingKey { case product, version, name; case installationID = "id" }
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(product: fields.decode(String.self, forKey: .product), version: fields.decode(String.self, forKey: .version),
            installationID: fields.decode(String.self, forKey: .installationID), name: fields.decode(String.self, forKey: .name))
    }
}
public struct ServerHealth: Codable, Sendable, Equatable {
    public let status: String
    public let serviceRunning: Bool
    public let version: String
    public init(status: String, serviceRunning: Bool, version: String) {
        self.status = status; self.serviceRunning = serviceRunning; self.version = version
    }
    enum CodingKeys: String, CodingKey { case status, version; case serviceRunning = "service_running" }
}
public struct BootstrapSnapshot: Sendable, Equatable {
    public let deployment: DeploymentURL
    public let health: ServerHealth
    public let identity: ServerIdentity
    public let auth: AuthStatus
    public var phase: BootstrapPhase { auth.bootstrapPhase }
    public init(deployment: DeploymentURL, health: ServerHealth, identity: ServerIdentity, auth: AuthStatus) {
        self.deployment = deployment; self.health = health; self.identity = identity; self.auth = auth
    }
}
extension AuthStatus {
    public var bootstrapPhase: BootstrapPhase {
        if mode == "undecided" || firstRun == true { return .chooseAuthentication }
        if !enabled { return .ready }
        if setupRequired { return .setupAdministrator }
        // Native mobile control sessions are read-ready; TV and unknown future kinds remain excluded.
        if authenticated && (authKind == nil || authKind == "browser" || authKind == "session" || authKind == "mobile") { return .ready }
        return .signIn
    }
}

extension FiestaBoardService {
    public func bootstrap() async throws -> BootstrapSnapshot { throw FiestaBoardError.unsupportedOperation }
    public func setAuthenticationPreference(enabled: Bool, setupToken: String? = nil) async throws -> AuthStatus { throw FiestaBoardError.unsupportedOperation }
    public func setupAdministrator(username: String, password: String, setupToken: String? = nil) async throws -> AuthStatus { throw FiestaBoardError.unsupportedOperation }
    public func login(username: String, password: String, rememberMe: Bool) async throws -> AuthStatus {
        guard !rememberMe else { throw FiestaBoardError.unsupportedOperation }
        return try await login(username: username, password: password)
    }
}
