import Foundation

/// Ephemeral validated dispatch input. Neither this value nor the flow is persisted or logged.
public struct PasswordResetAttempt: Sendable {
    public let id: UUID
    public let code: String
    public let newPassword: String
}

public struct PasswordResetFlow: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case instructions, enterCode, submitting, passwordChanged, uncertain }
    public enum Field: Sendable, Hashable { case code, newPassword, confirmation }
    public enum Result: Sendable { case changed, invalidCode, unknownOutcome }
    public private(set) var phase: Phase = .instructions
    public private(set) var invalidFields: Set<Field> = []
    private var pending: UUID?
    public init() {}

    public mutating func enterCode() {
        guard phase == .instructions else { return }
        phase = .enterCode; invalidFields = []
    }

    public mutating func prepare(code: String, newPassword: String, confirmation: String) -> PasswordResetAttempt? {
        guard phase == .enterCode else { return nil }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        invalidFields = []
        if !(1...256).contains(code.unicodeScalars.count) { invalidFields.insert(.code) }
        if !(8...1024).contains(newPassword.unicodeScalars.count) { invalidFields.insert(.newPassword) }
        if confirmation != newPassword { invalidFields.insert(.confirmation) }
        guard invalidFields.isEmpty else { return nil }
        let id = UUID(); pending = id; phase = .submitting
        return PasswordResetAttempt(id: id, code: code, newPassword: newPassword)
    }

    public mutating func receive(_ result: Result, for id: UUID) {
        guard phase == .submitting, pending == id else { return }
        pending = nil; invalidFields = []
        switch result {
        case .changed: phase = .passwordChanged
        case .invalidCode: phase = .enterCode; invalidFields = [.code]
        case .unknownOutcome: phase = .uncertain
        }
    }

    public mutating func cancel() {
        pending = nil; phase = .instructions; invalidFields = []
    }
}
