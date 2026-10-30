import Foundation

/// A step of the pairing handshake, numbered in the handshake's own `MSG` field.
struct ApplePasswordsHandshakeStage: Hashable, Sendable {
    // MARK: - Static Variables

    static let clientKeyExchange = ApplePasswordsHandshakeStage(number: 0)
    static let serverKeyExchange = ApplePasswordsHandshakeStage(number: 1)
    static let clientVerification = ApplePasswordsHandshakeStage(number: 2)
    static let serverVerification = ApplePasswordsHandshakeStage(number: 3)

    // MARK: - Variables

    let number: Int

    // MARK: - Initializers

    private init(number: Int) {
        self.number = number
    }

    // MARK: - Actions - Matching

    /// Whether the helper's `MSG` names this stage. It is a number or a string of one.
    func isNamed(by value: ApplePasswordsLooseInteger?) -> Bool {
        value?.value == number
    }
}
