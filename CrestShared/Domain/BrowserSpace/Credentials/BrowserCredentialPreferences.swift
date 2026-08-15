import Foundation

struct BrowserCredentialPreferences: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var syncsCrestPasswordsWithICloud: Bool
    var alsoOffersSaveToSystemPasswords: Bool

    init(
        isEnabled: Bool = true,
        syncsCrestPasswordsWithICloud: Bool,
        alsoOffersSaveToSystemPasswords: Bool
    ) {
        self.isEnabled = isEnabled
        self.syncsCrestPasswordsWithICloud = syncsCrestPasswordsWithICloud
        self.alsoOffersSaveToSystemPasswords = alsoOffersSaveToSystemPasswords
    }

    static let `default` = BrowserCredentialPreferences(
        isEnabled: true,
        syncsCrestPasswordsWithICloud: true,
        alsoOffersSaveToSystemPasswords: false
    )

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case syncsCrestPasswordsWithICloud
        case alsoOffersSaveToSystemPasswords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? true
        syncsCrestPasswordsWithICloud = try container.decodeIfPresent(
            Bool.self,
            forKey: .syncsCrestPasswordsWithICloud
        ) ?? true
        alsoOffersSaveToSystemPasswords = try container.decodeIfPresent(
            Bool.self,
            forKey: .alsoOffersSaveToSystemPasswords
        ) ?? false
    }
}
