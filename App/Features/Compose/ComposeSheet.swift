import SwiftUI
import FiestaBoardKit
import FiestaBoardAppState
import FiestaBoardDocuments
import FiestaBoardEditorState

/// Opens only the current protected principal's local draft. Offline display
/// descriptors are presentation evidence and cannot become live authority.
struct ComposeSheet: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var connection: ConnectionModel
    @ObservedObject var status: BoardStatus
    let buffers: ComposeBufferStore
    @State private var session: ComposeSession?
    @State private var issue: String?
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let session {
                ComposeEditor(session: session, store: store, status: status, buffers: buffers,
                    verifyTarget: verifyTarget)
            } else {
                NavigationStack {
                    Group {
                        if loading { ProgressView("Opening your draft…") }
                        else { ContentUnavailableView("Compose unavailable", systemImage: "square.and.pencil",
                            description: Text(issue ?? "Sign in to open your draft for this hub.")) }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
            }
        }
        .presentationDetents([.large])
        .presentationSizing(.form)
        .presentationDragIndicator(.visible)
        .task(id: connection.composePrincipal) {
            if let session, connection.composePrincipal?.identity != session.scope.identity
                || connection.composePrincipal?.connectionID != session.scope.connectionID {
                session.close(); self.session = nil
            }
            await open()
        }
        .onChange(of: store.networkAvailable) { _, _ in updateConnectivity() }
        .onChange(of: store.hubReachable) { _, _ in updateConnectivity() }
        .onDisappear {
            let closing = session
            Task { _ = try? await closing?.persistBuffer(); closing?.close() }
        }
    }
    private var online: Bool { store.networkAvailable && store.hubReachable == true && store.composePrincipal?.verifiedOnline == true }
    private func updateConnectivity() { session?.setOnline(online) }

    private func open() async {
        guard session == nil else { return }
        loading = true; defer { loading = false }
        guard let proof = connection.composePrincipal,
              let deployment = connection.selectedSavedHub?.deployment,
              deployment.description == proof.identity.deploymentID else { return }
        do {
            let saved = try await buffers.load(proof.identity)
            guard connection.composePrincipal == proof else { return }
            let desiredID = saved?.targetID ?? store.selectedBoardID
            if online, let desiredID, desiredID != store.selectedBoardID,
               store.boards.contains(where: { $0.id == desiredID }) {
                await store.selectBoard(desiredID).value
            }
            guard connection.composePrincipal == proof else { return }
            let detail = store.board.flatMap { $0.summary.id == desiredID ? $0 : nil }
            let presentation = detail.map(Self.presentation) ?? saved?.targetPresentation
            guard let targetID = desiredID, let presentation,
                  presentation.id == targetID else {
                issue = "Your saved display is unavailable. Reconnect to the hub and choose a display."
                return
            }
            let target = try BoardTarget(deployment: deployment, boardID: targetID)
            let verified = online && detail != nil && store.composePrincipal == proof
            let scope = ComposeScope(identity: proof.identity, connectionID: proof.connectionID, target: target,
                rows: presentation.rows, cols: presentation.cols, verifiedOnline: verified, presentation: presentation)
            let next = ComposeSession(scope: scope, online: verified) { captured in
                guard let principal = store.composePrincipal,
                      let detail = store.board,
                      principal.identity == captured.scope.identity,
                      principal.connectionID == captured.scope.connectionID,
                      detail.summary.id == captured.scope.target.boardID else { throw FiestaBoardError.invalidTarget }
                let request = ComposeRequest(principal: principal, target: captured.scope.target,
                    text: captured.input.text, lineMetadata: captured.input.lineMetadata,
                    geometry: try ComposeGeometry(summary: detail.summary), duration: captured.input.duration, silence: captured.input.silence)
                return try await store.previewCompose(request)
            }
            _ = try await next.bindBuffer(buffers)
            guard connection.composePrincipal == proof else { next.close(); return }
            session = next
            if verified, !next.input.text.isEmpty { next.retryPreview() }
        } catch { issue = "Your draft could not be opened. Its saved contents have been kept." }
    }
    private func verifyTarget(_ id: String, _ session: ComposeSession) async {
        guard !store.commandBusy, !store.refreshing, !store.needsReadback, store.pageLibrary?.needsReview != true else { return }
        if !online {
            if connection.phase == .unreachable { await connection.retrySavedHub().value }
            else { await store.probeReachability().value }
        }
        guard online else { return }
        if store.selectedBoardID != id { await store.selectBoard(id).value }
        else { await store.refresh().value }
        guard online, let proof = store.composePrincipal, let detail = store.board,
              detail.summary.id == id, proof.identity == session.scope.identity,
              proof.connectionID == session.scope.connectionID,
              session.scope.target.deployment == connection.selectedSavedHub?.deployment,
              let target = try? BoardTarget(deployment: session.scope.target.deployment, boardID: id) else { return }
        let descriptor = Self.presentation(detail)
        session.changeScope(.init(identity: proof.identity, connectionID: proof.connectionID,
            target: target,
            rows: detail.summary.rows, cols: detail.summary.cols, verifiedOnline: true, presentation: descriptor))
        session.setOnline(true)
        session.retryPreview()
        _ = try? await session.persistBuffer()
    }
    private static func presentation(_ detail: BoardDetail) -> ComposeBufferTarget {
        let s = detail.summary
        return .init(id: s.id, name: s.name, deviceType: s.deviceType, rows: s.rows, cols: s.cols,
            deviceModel: s.deviceModel, charset: s.charset, drawingData: try? detail.drawing?.presentationData())
    }
}
