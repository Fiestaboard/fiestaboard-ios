import Foundation
import FiestaBoardDocuments

/// Nonsecret buffer authority. An offline proof never grants a transport bearer
/// or live control capability; it only selects the matching on-device buffer.
public struct ComposePrincipalProof: Equatable, Sendable {
    public let identity: ComposeBufferIdentity
    public let connectionID: UUID
    public let verifiedOnline: Bool
    init(deployment: DeploymentURL, installationID: String, principalID: String, connectionID: UUID, verifiedOnline: Bool) {
        identity = .init(deploymentID: deployment.description, installationID: installationID, principalID: principalID)
        self.connectionID = connectionID; self.verifiedOnline = verifiedOnline
    }
}
public protocol ComposePrincipalProviding: Sendable {
    func composePrincipal() async -> ComposePrincipalProof?
    func rememberedComposePrincipal(installationID: String) async -> ComposePrincipalProof?
}
