import SwiftUI
import FiestaBoardAppState

struct SetupView: View {
    @ObservedObject var model: ConnectionModel
    let choosingAuthentication: Bool
    @FocusState private var focus: Field?
    private enum Field { case username, password, proof }
    var body: some View {
        Section(choosingAuthentication ? "Choose authentication" : "Create administrator") {
            if model.requiresSetupProof {
                SecureField("Stored MCP token", text: $model.setupToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .proof).accessibilityIdentifier("connectionSetupProof")
                Text("This server requires its stored MCP token to prove you can finish setup. Find it in the server's configuration. It is cleared from this form for each attempt.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if choosingAuthentication {
                Text("Choose whether this server requires an administrator sign-in. Its environment may control this setting.")
                Button("Require sign-in") { focus = nil; model.setAuthentication(enabled: true) }
                Button("Continue without sign-in") { focus = nil; model.setAuthentication(enabled: false) }
            } else {
                TextField("Administrator username", text: $model.username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .username).submitLabel(.next).onSubmit { focus = .password }
                SecureField("New password", text: $model.password).textContentType(.newPassword)
                    .focused($focus, equals: .password).accessibilityIdentifier("connectionNewPassword")
                Toggle("Remember sign-in", isOn: $model.rememberMe)
                Button("Create administrator") { focus = nil; model.setupAdministrator() }
                    .disabled(model.username.isEmpty || model.password.isEmpty)
                Text("Your password and setup proof are cleared from this form immediately when you submit.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.disabled(model.busy || model.requiresStateCheck)
    }
}
