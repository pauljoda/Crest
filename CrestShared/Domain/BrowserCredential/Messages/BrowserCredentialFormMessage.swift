import Foundation

/// A narrowly validated message from Crest's isolated WebKit content world.
/// It deliberately cannot be encoded, and its textual representations never
/// include the password received during a submit event.
struct BrowserCredentialFormMessage: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    static let contractVersion = 1
    private static let maximumFormIDLength = 256
    private static let maximumUsernameLength = 1_024
    private static let maximumPasswordLength = 16_384

    let event: BrowserCredentialFormEvent
    let formID: String?
    let username: String?
    let password: String?
    let passwordKind: BrowserCredentialPasswordKind?
    let isTrustedUserEvent: Bool
    let hasVisiblePasswordField: Bool?

    init?(body: Any) {
        guard let dictionary = body as? [String: Any],
              dictionary["version"] as? Int == Self.contractVersion,
              let eventValue = dictionary["event"] as? String,
              let event = BrowserCredentialFormEvent(rawValue: eventValue) else {
            return nil
        }

        let formID = Self.nonemptyString(
            dictionary["formID"],
            maximumLength: Self.maximumFormIDLength
        )
        let username = Self.nonemptyString(
            dictionary["username"],
            maximumLength: Self.maximumUsernameLength
        )
        let password = Self.nonemptyString(
            dictionary["password"],
            maximumLength: Self.maximumPasswordLength
        )
        let passwordKind = (dictionary["passwordKind"] as? String)
            .flatMap(BrowserCredentialPasswordKind.init(rawValue:))
        let isTrustedUserEvent = dictionary["trusted"] as? Bool ?? false
        let hasVisiblePasswordField = dictionary["hasVisiblePasswordField"] as? Bool
        let containsUsername = dictionary.keys.contains("username")
        let containsPassword = dictionary.keys.contains("password")
        let containsPasswordKind = dictionary.keys.contains("passwordKind")
        let hasInvalidUsername = containsUsername && username == nil
        let hasInvalidPassword = containsPassword && password == nil
        let hasInvalidPasswordKind = containsPasswordKind && passwordKind == nil

        switch event {
        case .username:
            guard formID != nil,
                  username != nil,
                  isTrustedUserEvent,
                  !containsPassword,
                  !containsPasswordKind else { return nil }
        case .focus:
            guard formID != nil,
                  isTrustedUserEvent,
                  !hasInvalidUsername,
                  !containsPassword,
                  passwordKind != nil else { return nil }
        case .submit:
            guard formID != nil,
                  isTrustedUserEvent,
                  !hasInvalidUsername,
                  !hasInvalidPassword,
                  !hasInvalidPasswordKind,
                  password != nil,
                  passwordKind != nil else { return nil }
        case .documentState:
            guard hasVisiblePasswordField != nil,
                  !containsUsername,
                  !containsPassword,
                  !containsPasswordKind else { return nil }
        }

        self.event = event
        self.formID = formID
        self.username = username
        self.password = password
        self.passwordKind = passwordKind
        self.isTrustedUserEvent = isTrustedUserEvent
        self.hasVisiblePasswordField = hasVisiblePasswordField
    }

    var description: String {
        "BrowserCredentialFormMessage(event: \(event.rawValue), formID: \(formID ?? "none"), username: \(username ?? "none"), password: <redacted>)"
    }

    var debugDescription: String { description }

    private static func nonemptyString(_ value: Any?, maximumLength: Int) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }
}
