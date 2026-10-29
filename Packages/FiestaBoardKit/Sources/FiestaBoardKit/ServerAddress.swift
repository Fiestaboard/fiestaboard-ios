import Foundation

public enum ServerAddress {
    /// Missing schemes default to HTTPS. HTTP is inferred only following the user's deliberate local HTTP choice.
    public static func parse(_ input: String, allowLocalHTTP: Bool = false) throws -> DeploymentURL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("://") { return try DeploymentURL(value, allowLocalHTTP: allowLocalHTTP) }
        // A colon may introduce a port, but must never repair an explicit malformed scheme.
        if !value.hasPrefix("["), let colon = value.firstIndex(of: ":") {
            let remainder = value[value.index(after: colon)...].split(separator: "/", omittingEmptySubsequences: false).first ?? ""
            guard !remainder.isEmpty, remainder.allSatisfy(\.isNumber) else { throw FiestaBoardError.invalidDeployment }
        }
        let scheme = allowLocalHTTP ? "http" : "https"
        return try DeploymentURL(scheme + "://" + value, allowLocalHTTP: allowLocalHTTP)
    }
}
