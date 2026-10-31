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

public enum PageManagementOperation: Sendable, CaseIterable { case create, delete }
public extension CapabilityPolicy {
    static func allowsPageManagement(_ operation: PageManagementOperation, version: String?, isDev: Bool, optedIn: Bool) -> Bool {
        guard optedIn, !isDev else { return false }
        switch operation { case .create: return version == "10.1.20"; case .delete: return version == "10.1.20" }
    }
}

public extension CapabilityPolicy {
    /// The legacy evaluation endpoints advertise no capability protocol. This
    /// bounded inference follows reviewed 10.x request contracts through 10.3.2;
    /// it does not enable live rendering, page storage or display commands.
    static func allowsLegacyTemplateEvaluation(runningVersion: String?, isDev: Bool) -> Bool {
        guard !isDev, let runningVersion else { return false }
        let parts = runningVersion.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let value = Int(part) else { return false }
            numbers.append(value)
        }
        guard numbers[0] == 10 else { return false }
        return numbers[1] < 3 || (numbers[1] == 3 && numbers[2] <= 2)
    }
}
