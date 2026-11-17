import SwiftUI
import Network

/// Path changes never claim that the hub responded. BoardStore owns that evidence.
@MainActor final class ShellNetwork: ObservableObject {
    @Published private(set) var available = true
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in self?.available = available }
        }
        monitor.start(queue: DispatchQueue(label: "FiestaBoard.shell.path"))
    }
    deinit { monitor.cancel() }
}
