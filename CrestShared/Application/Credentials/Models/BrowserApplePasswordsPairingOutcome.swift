import Foundation

/// How one step of pairing with Apple Passwords ended, as the prompt needs it.
/// The Mac maps the helper's errors to these; shared code reads the facts.
struct BrowserApplePasswordsPairingOutcome: Hashable, Sendable {
    // MARK: - Static Variables

    /// The helper is showing a code.
    static let codeShown = BrowserApplePasswordsPairingOutcome(
        name: "codeShown", isPaired: false, asksForNewCode: false, endsPairing: false, message: nil)
    static let paired = BrowserApplePasswordsPairingOutcome(
        name: "paired", isPaired: true, asksForNewCode: false, endsPairing: true, message: nil)
    /// The code does not match, and the challenge is spent.
    static let wrongCode = BrowserApplePasswordsPairingOutcome(
        name: "wrongCode", isPaired: false, asksForNewCode: true, endsPairing: false,
        message: LocalizedStringResource("That code doesn’t match. Enter the new one."))
    /// The code is not six digits, and the same challenge stays open.
    static let malformedCode = BrowserApplePasswordsPairingOutcome(
        name: "malformedCode", isPaired: false, asksForNewCode: false, endsPairing: false,
        message: LocalizedStringResource("Enter the 6-digit code."))
    static let challengeExpired = BrowserApplePasswordsPairingOutcome(
        name: "challengeExpired", isPaired: false, asksForNewCode: true, endsPairing: false, message: nil)
    static let failed = BrowserApplePasswordsPairingOutcome(
        name: "failed", isPaired: false, asksForNewCode: false, endsPairing: true,
        message: LocalizedStringResource("Crest couldn’t pair with Apple Passwords."))

    // MARK: - Variables

    let name: String
    let isPaired: Bool
    /// Whether the helper's challenge is spent, so a fresh code is requested.
    let asksForNewCode: Bool
    /// Whether the prompt leaves code entry, back to the pairing row.
    let endsPairing: Bool
    /// What the prompt tells the person, if anything.
    let message: LocalizedStringResource?

    // MARK: - Actions - Identity

    static func == (lhs: BrowserApplePasswordsPairingOutcome, rhs: BrowserApplePasswordsPairingOutcome) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
