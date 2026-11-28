import Foundation

/// The sections of the Autofill settings page.
///
/// Passwords, passkeys, addresses and payment cards.
extension BrowserSettingsSection {
    static let passwordsSpace = BrowserSettingsSection(
        name: "passwordsSpace", title: "Space",
        searchTerms: "choose Space")
    static let crestPasswords = BrowserSettingsSection(
        name: "crestPasswords", title: "Crest Passwords",
        searchTerms: "passwords credentials autofill iCloud Keychain synchronization use Crest Passwords manage")
    static let savedPasswords = BrowserSettingsSection(
        name: "savedPasswords", title: "Saved passwords",
        searchTerms:
            "saved passwords search sort import export select add password never saved sites one-time codes authenticator two-factor"
    )
    static let systemPasskeys = BrowserSettingsSection(
        name: "systemPasskeys", title: "System passkeys",
        searchTerms: "passkeys system access")
    static let addresses = BrowserSettingsSection(
        name: "addresses", title: "Addresses",
        searchTerms: "addresses autofill add address")
    static let paymentCards = BrowserSettingsSection(
        name: "paymentCards", title: "Payment cards",
        searchTerms: "payment cards credit card add card")
}
