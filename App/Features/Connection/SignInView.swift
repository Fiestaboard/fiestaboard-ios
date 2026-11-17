import SwiftUI
import FiestaBoardAppState

struct SignInView: View {
    @ObservedObject var model: ConnectionModel
    @FocusState private var focus: Field?
    @State private var revealPassword = false
    private enum Field { case username, password }
    @Environment(\.colorScheme) private var appearance
    private var palette: OnboardingPalette { .init(appearance: appearance) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in to FiestaBoard").font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text("Enter your administrator credentials to continue.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Username").font(.subheadline.weight(.medium))
                TextField("Username", text: $model.username)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .username).submitLabel(.next).onSubmit { focus = .password }
                    .modifier(OnboardingFieldStyle()).accessibilityIdentifier("connectionUsername")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.subheadline.weight(.medium))
                HStack {
                    Group {
                        if revealPassword { TextField("Password", text: $model.password) }
                        else { SecureField("Password", text: $model.password) }
                    }
                    .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .password).submitLabel(.go).onSubmit { signIn() }
                    .privacySensitive().accessibilityIdentifier("connectionPassword")
                    Button { revealPassword.toggle() } label: { Image(systemName: revealPassword ? "eye.slash" : "eye") }
                        .accessibilityLabel(revealPassword ? "Hide password" : "Show password")
                        .frame(minWidth: 44, minHeight: 44)
                }.modifier(OnboardingFieldStyle(verticalPadding: 0))
                if model.signInPasswordRejected {
                    Text("The username or password is incorrect.").font(.footnote).foregroundStyle(palette.color("destructive"))
                        .accessibilityIdentifier("signInCredentialError")
                }
            }
            Toggle("Keep me logged in", isOn: $model.rememberMe)
            Text("Remember sign-in stores a session securely for this installation. Your password is never saved.")
                .font(.footnote).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = model.loginRetryDeadline?.remainingSeconds(at: timeline.date) ?? 0
                VStack(spacing: 12) {
                    if remaining > 0 {
                        OnboardingNotice(title: "Too many tries", detail: "Sign-in is paused to protect your hub. You can try again in \(countdown(remaining)).", symbol: "lock", tone: "destructive")
                            .accessibilityIdentifier("signInLockout")
                    }
                    OnboardingAction(title: remaining > 0 ? "Try again in \(countdown(remaining))" : "Sign in", action: signIn)
                        .disabled(model.busy || model.requiresStateCheck || remaining > 0 || model.username.isEmpty || model.password.isEmpty)
                        .accessibilityIdentifier("connectionSignIn")
                }
            }
            Button("Forgot password?") { focus = nil; revealPassword = false; model.beginPasswordReset() }
                .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("forgotPassword")
                .disabled(model.busy || model.requiresStateCheck)
            if let host = model.snapshot?.deployment.description {
                Text("Your password goes only to your hub at \(host). If this hub has sign-in disabled, we skip this step.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.disabled(model.busy)
    }
    private func countdown(_ seconds: Int) -> String { "\(seconds / 60):" + String(format: "%02d", seconds % 60) }
    private func signIn() { focus = nil; revealPassword = false; model.finishPasswordReset(); model.signIn() }
}
