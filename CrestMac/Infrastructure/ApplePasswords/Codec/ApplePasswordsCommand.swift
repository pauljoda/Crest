import Foundation

/// A message kind of the helper's protocol. Replies carry no correlation
/// identifier, so a reply belongs to the request with the same command.
struct ApplePasswordsCommand: Hashable, Sendable {
    // MARK: - Static Variables

    static let end = ApplePasswordsCommand(number: 0)
    static let handshake = ApplePasswordsCommand(number: 2)
    static let getLoginNames = ApplePasswordsCommand(number: 4)
    static let getPassword = ApplePasswordsCommand(number: 5)
    static let setPassword = ApplePasswordsCommand(number: 6)
    static let passwordsDisabled = ApplePasswordsCommand(number: 9, push: .passwordsDisabled)
    static let reloginNeeded = ApplePasswordsCommand(number: 10, push: .reloginNeeded)
    /// Tells the helper which tab is in front or was closed. It has no reply.
    static let tabEvent = ApplePasswordsCommand(number: 8)
    /// Opens the Passwords app on a site. It has no reply.
    static let launchPasswordsApp = ApplePasswordsCommand(number: 13)
    static let getCapabilities = ApplePasswordsCommand(number: 14)
    /// Pushed when a one-time code arrives. It only asks an open code list to refresh.
    static let oneTimeCodeAvailable = ApplePasswordsCommand(number: 15, push: .oneTimeCodeAvailable)
    static let getOneTimeCodes = ApplePasswordsCommand(number: 16)
    static let didFillOneTimeCode = ApplePasswordsCommand(number: 17)
    /// Tells the helper the person gave up on the code. It has no reply.
    static let cancelPairing = ApplePasswordsCommand(number: 19)

    /// Every command the codec knows. The rest of the protocol (icons) is never
    /// sent, and a message with another number is ignored.
    static let all: [ApplePasswordsCommand] = [
        end, handshake, getLoginNames, getPassword, setPassword, tabEvent, passwordsDisabled, reloginNeeded,
        launchPasswordsApp, getCapabilities, oneTimeCodeAvailable, getOneTimeCodes, didFillOneTimeCode, cancelPairing,
    ]

    // MARK: - Variables

    let number: Int
    /// What the helper announces on its own with this command, if it does.
    let push: ApplePasswordsPush?
    /// Whether the helper may send this command without being asked.
    let isUnsolicited: Bool

    // MARK: - Initializers

    private init(number: Int, push: ApplePasswordsPush? = nil, isUnsolicited: Bool = false) {
        self.number = number
        self.push = push
        self.isUnsolicited = isUnsolicited || push != nil
    }

    // MARK: - Actions - Lookup

    static func numbered(_ number: Int) -> ApplePasswordsCommand? {
        all.first { $0.number == number }
    }
}
