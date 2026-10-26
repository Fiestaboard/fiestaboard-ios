import Foundation
import Combine
import FiestaBoardKit

public struct PageDocumentSnapshot: Sendable {
    public let id: String
    public let deployment: DeploymentURL
    public let data: Data
}

public enum RemoteLogoutState: Sendable, Equatable { case pending, succeeded, failed }
public enum ActionPayload: Sendable { case text(String), page(String), configuration(BoardPatch), restore }
/// A confirmation binds the exact payload to the deployment, board and current UI generation.
public struct PreparedAction: Identifiable, Sendable {
    public let id = UUID()
    public let target: BoardTarget
    public let payload: ActionPayload
    public let boardName: String
    public let isDemo: Bool
    let generation: UInt64
}

// Combine keeps this draft buildable where compiler macro sandbox execution is unavailable.
@MainActor public final class BoardStore: ObservableObject {
    @Published public private(set) var status: ConnectionStatus?
    @Published public private(set) var boards: [BoardSummary] = []
    @Published public private(set) var pages: [Page] = []
    @Published public private(set) var board: BoardDetail?
    @Published public private(set) var selectedBoardID: String?
    @Published public private(set) var message: String?
    @Published public private(set) var remoteLogoutState: RemoteLogoutState?
    @Published public private(set) var connecting = false
    @Published public private(set) var refreshing = false
    @Published private var readbackTargets: Set<BoardTarget> = []
    public var needsReadback: Bool { target.map { readbackTargets.contains($0) } ?? false }
    @Published public private(set) var connectionLabel = "Disconnected"
    private var generation: UInt64 = 0
    private var service: (any FiestaBoardService)?
    private var connectionTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    @Published private var inFlight: Set<BoardTarget> = []
    private var usedActions: Set<UUID> = []
    public var commandBusy: Bool { target.map { inFlight.contains($0) } ?? false }
    public var canWrite: Bool {
        status != nil && status?.access != .readOnly && target != nil && !connecting && !refreshing && !commandBusy && !needsReadback
    }
    private var target: BoardTarget? {
        guard let service, let id = selectedBoardID else { return nil }
        return try? BoardTarget(deployment: service.deployment, boardID: id)
    }
    public init() {}

    @discardableResult public func connect(_ next: any FiestaBoardService, allowCandidateWrites: Bool = false,
                                           username: String = "", password: String = "") -> Task<Void, Never> {
        disconnect()
        service = next
        connectionLabel = next.isDemo ? "Demo · simulated" : next.deployment.description
        connecting = true
        let token = generation
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let auth = try await next.authStatus()
                guard valid(token) else { return }
                guard !auth.setupRequired else { throw StoreError.setupRequired }
                if auth.enabled && !auth.authenticated {
                    guard !username.isEmpty && !password.isEmpty else { throw FiestaBoardError.unauthenticated }
                    _ = try await next.login(username: username, password: password)
                }
                guard valid(token) else { return }
                let result = try await next.connect(allowCandidateWrites: allowCandidateWrites)
                guard valid(token) else { return }
                let list = try await next.boards()
                guard valid(token) else { return }
                let library = try await next.pages()
                guard valid(token) else { return }
                var detail: BoardDetail?
                if let first = list.first {
                    detail = try await next.board(BoardTarget(deployment: next.deployment, boardID: first.id))
                }
                guard valid(token) else { return }
                status = result; boards = list; pages = library
                selectedBoardID = list.first?.id; board = detail
                if let target, !inFlight.contains(target) { readbackTargets.remove(target) }
            } catch {
                guard valid(token) else { return }
                if !handleAuthenticationLoss(error) { message = safeDescription(error) }
            }
            if valid(token) { connecting = false }
        }
        connectionTask = task
        return task
    }

    @discardableResult public func reconnect(allowCandidateWrites: Bool) -> Task<Void, Never> {
        guard let service else { return Task {} }
        return connect(service, allowCandidateWrites: allowCandidateWrites)
    }

    public func disconnect() {
        generation &+= 1
        connectionTask?.cancel(); refreshTask?.cancel(); commandTask?.cancel()
        connectionTask = nil; refreshTask = nil; commandTask = nil
        service = nil; status = nil; boards = []; pages = []; board = nil; selectedBoardID = nil
        connecting = false; refreshing = false; message = nil; remoteLogoutState = nil
        connectionLabel = "Disconnected"; usedActions = []
    }

    /// Drops the local session immediately; the captured old service revokes its session separately.
    @discardableResult public func logout() -> Task<Void, Never> {
        let old = service
        disconnect()
        guard let old else { return Task {} }
        let token = generation
        let server = old.deployment.description
        remoteLogoutState = .pending
        message = "Disconnected locally. Signing out of \(server)…"
        return Task { [weak self] in
            do {
                try await old.logout()
                guard let self, generation == token else { return }
                remoteLogoutState = .succeeded
                message = "Disconnected locally. Server sign-out confirmed for \(server)."
            } catch {
                guard let self, generation == token else { return }
                remoteLogoutState = .failed
                message = "Disconnected locally. Server sign-out could not be confirmed for \(server); the server session may still be active. Sign out in the server’s web interface if needed."
            }
        }
    }

    @discardableResult public func selectBoard(_ id: String) -> Task<Void, Never> {
        guard boards.contains(where: { $0.id == id }), !connecting else { return Task {} }
        generation &+= 1
        refreshTask?.cancel(); commandTask?.cancel()
        selectedBoardID = id; board = nil; message = nil; usedActions = []
        return refresh()
    }

    @discardableResult public func refresh() -> Task<Void, Never> {
        guard let service, status != nil, let target, !commandBusy else { return Task {} }
        refreshTask?.cancel()
        let token = generation
        refreshing = true
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await service.board(target)
                guard valid(token) else { return }
                acceptSnapshot(detail); readbackTargets.remove(target)
            } catch {
                guard valid(token) else { return }
                if !handleAuthenticationLoss(error) { message = safeDescription(error) }
            }
            if valid(token) { refreshing = false }
        }
        refreshTask = task
        return task
    }

    /// Bind local editor input to this connection; a late reply cannot become another server's document.
    public func loadPageDocument(id: String) async throws -> PageDocumentSnapshot {
        guard let service, status != nil, !connecting, pages.contains(where: { $0.id == id }) else {
            throw FiestaBoardError.invalidTarget
        }
        let token = generation
        let deployment = service.deployment
        do {
            let data = try await service.pageDocumentData(id: id)
            guard valid(token), self.service?.deployment == deployment else { throw FiestaBoardError.staleSession }
            return PageDocumentSnapshot(id: id, deployment: deployment, data: data)
        } catch {
            guard valid(token) else { throw FiestaBoardError.staleSession }
            _ = handleAuthenticationLoss(error)
            throw error
        }
    }

    public func prepare(_ payload: ActionPayload) -> PreparedAction? {
        guard canWrite, let target, let summary = boards.first(where: { $0.id == target.boardID }) else { return nil }
        switch payload {
        case .text(let value): guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        case .page(let id): guard pages.contains(where: { $0.id == id }) else { return nil }
        case .configuration(let patch):
            guard (try? patch.validate()) != nil else { return nil }
            if case .set(let id) = patch.defaultPage, !pages.contains(where: { $0.id == id }) { return nil }
        case .restore: break
        }
        return PreparedAction(target: target, payload: payload, boardName: summary.name,
                              isDemo: status?.isDemo == true, generation: generation)
    }

    @discardableResult public func confirm(_ action: PreparedAction) -> Task<Void, Never> {
        guard canWrite, action.generation == generation, action.target == target,
              !usedActions.contains(action.id), let service else { return Task {} }
        usedActions.insert(action.id)
        inFlight.insert(action.target)
        readbackTargets.insert(action.target)
        let token = generation
        let task = Task { [weak self] in
            guard let self else { return }
            defer { inFlight.remove(action.target) }
            do {
                let receipt: String
                switch action.payload {
                case .text(let value): receipt = Self.describe(try await service.sendText(value, to: action.target), simulated: action.isDemo)
                case .page(let id): receipt = Self.describe(try await service.selectPage(id: id, on: action.target), simulated: action.isDemo)
                case .configuration(let patch):
                    _ = try await service.updateBoard(patch, on: action.target)
                    receipt = (action.isDemo ? "Simulated — " : "") + "Board settings updated. Physical output is not verified."
                case .restore:
                    let result = try await service.restoreBoard(action.target)
                    receipt = (action.isDemo ? "Simulated — " : "") + (result.sent
                        ? "Restore write accepted. Physical output is not verified."
                        : "Restore did not send content. The pinned selection was retained.")
                }
                guard valid(token) else { return }
                message = receipt
                // Keep the receipt separate from readback; a failed refresh never upgrades the receipt.
                do {
                    let detail = try await service.board(action.target)
                    guard valid(token) else { return }
                    acceptSnapshot(detail); readbackTargets.remove(action.target)
                } catch {
                    guard valid(token) else { return }
                    readbackTargets.insert(action.target)
                    if !handleAuthenticationLoss(error, preservingReceipt: message) {
                        message = (message ?? "") + " Readback unavailable. Refresh before another action."
                    }
                }
            } catch {
                guard valid(token) else { return }
                if handleAuthenticationLoss(error) { return }
                message = (action.isDemo ? "Simulated — " : "") + safeDescription(error)
                // PATCH setters run in sequence. Even a 400/404/503 can follow an applied field.
                if case .configuration = action.payload {
                    readbackTargets.insert(action.target)
                    message = (message ?? "") + " Refresh before another action; some settings may have changed."
                } else {
                    switch error as? FiestaBoardError {
                    case .unknownMutationOutcome, .partialWrite: readbackTargets.insert(action.target)
                    default: readbackTargets.remove(action.target)
                    }
                }
            }
        }
        commandTask = task
        return task
    }
    private func acceptSnapshot(_ detail: BoardDetail) {
        board = detail
        if let index = boards.firstIndex(where: { $0.id == detail.summary.id }) { boards[index] = detail.summary }
    }
    /// Authentication loss ends this UI session at every request boundary. It also
    /// invalidates prepared actions; a readback failure cannot erase an earlier receipt.
    private func handleAuthenticationLoss(_ error: any Error, preservingReceipt: String? = nil) -> Bool {
        guard (error as? FiestaBoardError) == .unauthenticated else { return false }
        let server = connectionLabel
        disconnect()
        let prompt = "Authentication is required for \(server). Use the manual connection form to sign in again."
        message = preservingReceipt.map { $0 + " " + prompt } ?? prompt
        return true
    }
    private func valid(_ token: UInt64) -> Bool { token == generation && !Task.isCancelled }
    private func safeDescription(_ error: any Error) -> String {
        if let known = error as? FiestaBoardError { return known.localizedDescription }
        if let known = error as? StoreError { return known.localizedDescription }
        return "This draft could not complete the request. Refresh to try reading again."
    }
    private static func describe(_ result: MutationResult, simulated: Bool) -> String {
        let prefix = simulated ? "Simulated — " : ""
        let body: String
        switch result.disposition {
        case .accepted: body = "server acknowledged a send. Physical output is not verified."
        case .held: body = "held by the server; no send acknowledged."
        case .notSent: body = "server did not send this message."
        case .selectionStored: body = "selection stored; no send acknowledged."
        }
        return prefix + body + (result.silenced ? " Board is silenced." : "")
            + (result.deliveryFailed ? " Delivery failed." : "")
            + (result.warningCount > 0 ? " Server reported \(result.warningCount) warning(s)." : "")
    }
}
private enum StoreError: LocalizedError {
    case setupRequired
    var errorDescription: String? { "This server requires first-run setup. Complete setup in its web interface, then connect again." }
}
