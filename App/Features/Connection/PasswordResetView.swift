import SwiftUI
import UIKit
import FiestaBoardAppState

struct PasswordResetView: View {
    @ObservedObject var model: ConnectionModel
    @FocusState private var focus: Field?
    @State private var copied = false
    private enum Field { case code, password, confirmation }
    @Environment(\.colorScheme) private var appearance
    private var palette: OnboardingPalette { .init(appearance: appearance) }
    // Source-pinned hub command includes appuser; the older drawing omits this required option.
    private let command = "docker compose exec -u appuser fiestaboard python -m src.auth.password_reset"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.passwordResetFlow?.phase {
            case .instructions:
                instructions
            case .enterCode, .submitting:
                entry
            case .uncertain:
                OnboardingNotice(title: "We couldn't confirm the reset", detail: "The request may have reached your hub. Check its current state before starting a new attempt. This request will not be repeated.", tone: "warning")
                    .accessibilityIdentifier("resetUncertain")
                OnboardingAction(title: "Check hub state") {
                    focus = nil; model.cancelPasswordReset(); model.checkServerState()
                }.disabled(model.busy)
            case .passwordChanged:
                SignInView(model: model)
            case nil:
                EmptyView()
            }
        }
    }
    private var instructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset your password").font(.title.bold()).accessibilityAddTraits(.isHeader)
            Text("Your hub has no email, so a reset starts on the hub itself. Whoever runs your hub does this:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                Text("Get a one-time reset code").font(.headline)
                Text("1. On the computer that runs your hub, open a terminal.")
                Text("2. Run:")
                Text(command).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                Text("3. Copy the code it prints. It starts with fb_reset_ and works once, for 15 minutes.")
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.color("card"), in: RoundedRectangle(cornerRadius: 26))
            OnboardingAction(title: copied ? "Command copied" : "Copy command", primary: false) {
                UIPasteboard.general.setItems([["public.utf8-plain-text": command]], options: [.localOnly: true])
                copied = true
            }.accessibilityIdentifier("copyResetCommand")
            OnboardingAction(title: "I have a code") { model.enterPasswordResetCode(); focus = .code }
                .accessibilityIdentifier("haveResetCode")
        }
    }
    private var entry: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter the code and a new password").font(.title.bold()).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                Text("Reset code").font(.subheadline.weight(.medium))
                SecureField("Reset code", text: $model.resetCode)
                    .textContentType(.oneTimeCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .code).submitLabel(.next).onSubmit { focus = .password }
                    .modifier(OnboardingFieldStyle()).privacySensitive().accessibilityIdentifier("resetCode")
                Text("Paste the code the command printed.").font(.footnote).foregroundStyle(.secondary)
                if invalid(.code) {
                    Text("That code didn't work. It may have expired or already been used. Run the command again for a new code.")
                        .font(.footnote).foregroundStyle(palette.color("destructive")).accessibilityIdentifier("resetCodeError")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("New password").font(.subheadline.weight(.medium))
                SecureField("New password", text: $model.resetNewPassword)
                    .textContentType(.newPassword).focused($focus, equals: .password).submitLabel(.next)
                    .onSubmit { focus = .confirmation }.modifier(OnboardingFieldStyle())
                    .privacySensitive().accessibilityIdentifier("resetNewPassword")
                Text(invalid(.newPassword) ? "Use 8 to 1,024 characters." : "At least 8 characters.")
                    .font(.footnote).foregroundStyle(invalid(.newPassword) ? palette.color("destructive") : palette.color("muted-foreground"))
                    .accessibilityIdentifier("resetPasswordHelp")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm new password").font(.subheadline.weight(.medium))
                SecureField("Confirm new password", text: $model.resetConfirmation)
                    .textContentType(.newPassword).focused($focus, equals: .confirmation).submitLabel(.go)
                    .onSubmit { submit() }.modifier(OnboardingFieldStyle())
                    .privacySensitive().accessibilityIdentifier("resetConfirmation")
                if invalid(.confirmation) {
                    Text("The passwords must match exactly.").font(.footnote).foregroundStyle(palette.color("destructive"))
                        .accessibilityIdentifier("resetConfirmationError")
                }
            }
            OnboardingNotice(title: "This signs everything out", detail: "Every browser, TV and phone on this hub is signed out, including this one. Sign in again with the new password.", symbol: "exclamationmark.shield")
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = model.loginRetryDeadline?.remainingSeconds(at: timeline.date) ?? 0
                OnboardingAction(title: model.busy ? "Changing password…" : remaining > 0 ? "Try again in \(remaining) seconds" : "Reset password", action: submit)
                    .disabled(model.busy || model.requiresStateCheck || remaining > 0)
                    .accessibilityIdentifier("submitPasswordReset")
            }
            if model.busy { ProgressView("Changing password…") }
        }.disabled(model.busy)
    }
    private func invalid(_ field: PasswordResetFlow.Field) -> Bool { model.passwordResetFlow?.invalidFields.contains(field) == true }
    private func submit() { focus = nil; model.submitPasswordReset() }
}
