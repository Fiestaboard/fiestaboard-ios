import Foundation

/// A validated deployment identity, including its reverse-proxy prefix.
/// Percent-encoded deployment paths are deliberately unsupported in this draft.
public struct DeploymentURL: Hashable, Sendable, Codable, CustomStringConvertible {
    public let description: String
    public let allowsLocalHTTP: Bool

    public init(_ input: String, allowLocalHTTP: Bool = false) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains("\\"), !value.contains("%"),
              !value.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }),
              var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw FiestaBoardError.invalidDeployment
        }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0 == "." || $0 == ".." }),
              components.path.split(separator: "/").allSatisfy({ Self.validSegment(String($0)) }) else {
            throw FiestaBoardError.invalidDeployment
        }
        if scheme == "http" && (!allowLocalHTTP || !Self.isLocal(host)) {
            throw FiestaBoardError.insecureDeployment
        }
        components.scheme = scheme
        components.host = host
        components.path = components.path.split(separator: "/").map(String.init).map { "/" + $0 }.joined()
        guard let normalized = components.url?.absoluteString else { throw FiestaBoardError.invalidDeployment }
        description = normalized
        allowsLocalHTTP = scheme == "http"
    }

    public func apiURL(_ segments: [String]) throws -> URL {
        guard !segments.isEmpty, segments.allSatisfy(Self.validSegment),
              let url = URL(string: description + "/api/" + segments.joined(separator: "/")) else {
            throw FiestaBoardError.invalidPath
        }
        return url
    }

    static func validSegment(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95, 126].contains($0)
        }
    }

    private static func isLocal(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return true }
        if host.contains(":") {
            // Unique-local IPv6 and link-local IPv6. No zone identifiers/encoded hosts.
            return host.hasPrefix("fc") || host.hasPrefix("fd") || ["fe8", "fe9", "fea", "feb"].contains(where: host.hasPrefix)
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { return false }
        let bytes = parts.compactMap { Int($0) }
        return bytes[0] == 127 || bytes[0] == 10 || (bytes[0] == 192 && bytes[1] == 168) ||
            (bytes[0] == 172 && (16...31).contains(bytes[1])) || (bytes[0] == 169 && bytes[1] == 254)
    }

    private enum CodingKeys: String, CodingKey { case url, allowLocalHTTP }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(container.decode(String.self, forKey: .url),
                      allowLocalHTTP: container.decode(Bool.self, forKey: .allowLocalHTTP))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .url)
        try container.encode(allowsLocalHTTP, forKey: .allowLocalHTTP)
    }
}
