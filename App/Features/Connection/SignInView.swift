import SwiftUI
import FiestaBoardAppState

struct SignInView: View {
    @ObservedObject var model: ConnectionModel
    @FocusState private var focus: Field?
    private enum Field { case username, password }
    var body: some View {
        Section("Sign in") {
            TextField("Username", text: $model.username)
                .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focus, equals: .username).submitLabel(.next).onSubmit { focus = .password }
            SecureField("Password", text: $model.password).textContentType(.password)
                .focused($focus, equals: .password).submitLabel(.go).onSubmit { signIn() }
                .accessibilityIdentifier("connectionPassword")
            Toggle("Remember sign-in", isOn: $model.rememberMe)
            Text("Remember sign-in stores a session securely for this installation. Your password is never saved.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Sign in", action: signIn)
                .disabled(model.busy || model.requiresStateCheck || model.username.isEmpty || model.password.isEmpty)
                .accessibilityIdentifier("connectionSignIn")
        }.disabled(model.busy)
    }
    private func signIn() { focus = nil; model.signIn() }
}
