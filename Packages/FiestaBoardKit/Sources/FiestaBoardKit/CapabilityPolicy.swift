/// Exact versions and individual operations backed by captured contracts.
public enum BoardOperation: Sendable, CaseIterable { case sendText, selectPage, restore, scalarControls, conditionalDefault }
public enum CapabilityPolicy {
    public static func allows(_ operation: BoardOperation, version: String?, isDev: Bool, optedIn: Bool) -> Bool {
        guard optedIn, !isDev else { return false }
        switch operation {
        case .sendText, .selectPage, .restore, .scalarControls: return version == "10.0.0" || ["10.1.17", "10.1.20"].contains(version ?? "")
        case .conditionalDefault: return ["10.1.17", "10.1.20"].contains(version ?? "")
        }
    }
}
