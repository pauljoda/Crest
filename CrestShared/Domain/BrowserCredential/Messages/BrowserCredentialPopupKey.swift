import Foundation

// MARK: - Types

/// One press of a held key, told apart from an earlier press of the same key.
struct BrowserCredentialKeyPress: Equatable, Sendable {
    let id: UUID
    let key: BrowserCredentialPopupKey
}

/// A key the page script held back from the page while Crest's fill popup was
/// open for the focused field, and what it does to the popup: the arrows move
/// the selection, Return takes the selected row, Escape closes the popup.
struct BrowserCredentialPopupKey: Hashable, Sendable, Decodable {
    // MARK: - Static Variables

    static let down = BrowserCredentialPopupKey(name: "down", step: 1)
    static let up = BrowserCredentialPopupKey(name: "up", step: -1)
    static let choose = BrowserCredentialPopupKey(name: "choose", choosesSelection: true)
    static let dismiss = BrowserCredentialPopupKey(name: "dismiss", dismissesPopup: true)

    static let all: [BrowserCredentialPopupKey] = [down, up, choose, dismiss]

    // MARK: - Variables

    /// The content script's name for the key.
    let name: String

    /// How many rows the selection moves.
    let step: Int

    /// Whether the key takes the selected row.
    let choosesSelection: Bool

    /// Whether the key closes the popup without filling anything.
    let dismissesPopup: Bool

    // MARK: - Initializers

    private init(name: String, step: Int = 0, choosesSelection: Bool = false, dismissesPopup: Bool = false) {
        self.name = name
        self.step = step
        self.choosesSelection = choosesSelection
        self.dismissesPopup = dismissesPopup
    }

    /// The key the content script names; a key this build does not know fails
    /// to decode.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let key = Self.all.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown popup key \(name)")
        }
        self = key
    }
}
