/// Browser permission is requested only after the contextual explanation, never by manual entry.
public struct HubDiscoveryFlow: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case welcome, localNetworkExplanation, searching, chooseHub, manualAddress
    }
    public private(set) var phase: Phase = .welcome
    private var explained = false
    public init() {}
    public var mayBrowse: Bool { phase == .searching }

    public mutating func requestDiscovery() {
        phase = explained ? .searching : .localNetworkExplanation
    }
    public mutating func continueAfterExplanation() {
        guard phase == .localNetworkExplanation else { return }
        explained = true; phase = .searching
    }
    public mutating func enterAddress() { phase = .manualAddress }
    public mutating func stopSearching() {
        guard phase == .searching else { return }
        phase = .chooseHub
    }
}
