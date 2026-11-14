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


public extension CapabilityPolicy {
    /// Explicit document capability takes precedence over server version. The
    /// absent-field adapter is confined to the captured 10.1.2 revision contract
    /// (page-revision-v1.json; backend dadbc191e). This is document compatibility
    /// only: callers must still require opt-in, revision protocol and revision.
    static func supportsTemplateDocument(_ page: Page, version: String?, isDev: Bool) -> Bool {
        guard page.supportsTemplateEditing else { return false }
        if page.documentProtocol == "page-document-v1" { return true }
        return page.documentProtocol == nil && version == "10.1.2" && !isDev
    }
}


public enum ActionDisabledReason: Sendable, Equatable {
    case disconnected, noDisplay, unsupportedOperation, changesDisabled, busy, readbackRequired
    case unsupportedDocument, unsupportedRevisionProtocol, missingRevision
    public var message: String {
        switch self {
        case .disconnected: "Connect to a server to use this action."
        case .noDisplay: "Select a display before using this action."
        case .unsupportedOperation: "This server does not provide an operation or protocol supported by this app for this action. Use its web interface."
        case .unsupportedDocument: "Deletion of this document type or document protocol is unavailable in this app. Use the web interface."
        case .unsupportedRevisionProtocol: "This page does not provide a revision protocol supported for deletion. Use the web interface."
        case .missingRevision: "This page does not report a valid revision for safe deletion. Read the current page or use the web interface."
        case .changesDisabled: "This connection does not allow changes. Reconnect to try again."
        case .busy: "Wait for the current request to finish before using this action."
        case .readbackRequired: "The previous result needs review. Read current state before starting another action."
        }
    }
}
public extension CapabilityPolicy {
    static func boardActionDisabledReason(version: String?, isDev: Bool, optedIn: Bool) -> ActionDisabledReason? {
        guard allows(.selectPage, version: version, isDev: isDev, optedIn: true) else { return .unsupportedOperation }
        return optedIn ? nil : .changesDisabled
    }
    static func pageManagementDisabledReason(version: String?, isDev: Bool, optedIn: Bool) -> ActionDisabledReason? {
        guard allowsPageManagement(.create, version: version, isDev: isDev, optedIn: true) else { return .unsupportedOperation }
        return optedIn ? nil : .changesDisabled
    }
}

public extension CapabilityPolicy {
    /// Document eligibility precedes session opt-in: enabling changes cannot repair a document contract.
    static func pageDeletionDisabledReason(_ page: Page, version: String?, isDev: Bool,
                                          optedIn: Bool, isSimulated: Bool = false) -> ActionDisabledReason? {
        guard supportsTemplateDocument(page, version: version, isDev: isDev) else { return .unsupportedDocument }
        guard page.editProtocol == "page-revision-v1" else { return .unsupportedRevisionProtocol }
        guard let revision = page.revision, !revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              revision.count <= 256 else { return .missingRevision }
        guard DeploymentURL.validSegment(page.id),
              isSimulated || allowsPageManagement(.delete, version: version, isDev: isDev, optedIn: true) else {
            return .unsupportedOperation
        }
        return isSimulated || optedIn ? nil : .changesDisabled
    }
}

public extension CapabilityPolicy {
    /// Explicit v2 family permission; never inferred from the legacy evaluation version bound.
    static func supportsFlexibleDocument(_ page: Page) -> Bool {
        page.type == "flexible" && page.documentProtocol == "page-document-v2"
    }
    static func supportsEditableDocument(_ page: Page, version: String?, isDev: Bool) -> Bool {
        supportsTemplateDocument(page, version: version, isDev: isDev) || supportsFlexibleDocument(page)
    }
}
