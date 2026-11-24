import Foundation

/// What Settings › Autofill shows: a Space's passwords, with the one-time
/// codes their logins make, or the addresses and payment cards every Space
/// shares.
struct BrowserAutofillKind: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let passwords = BrowserAutofillKind(id: "passwords", title: "Passwords", isPerSpace: true)
    static let addresses = BrowserAutofillKind(id: "addresses", title: "Addresses", isPerSpace: false)
    static let cards = BrowserAutofillKind(id: "cards", title: "Payment Cards", isPerSpace: false)

    static let all = [passwords, addresses, cards]

    // MARK: - Variables

    let id: String
    let title: LocalizedStringResource
    /// Whether each Space keeps its own, so the Space picker applies.
    let isPerSpace: Bool

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
