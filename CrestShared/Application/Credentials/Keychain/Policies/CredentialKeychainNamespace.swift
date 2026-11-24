import Foundation

enum CredentialKeychainNamespace {
    static let productionPrefix = ProductIdentity.serviceNamespace

    static func service(
        for spaceID: UUID,
        prefix: String = productionPrefix
    ) -> String {
        "\(prefix).space.\(spaceID.uuidString.lowercased()).credential"
    }

    /// Where a Space keeps what its logins hold beside their passwords: notes
    /// and code keys, one item per login under the login's own account.
    static func extrasService(
        for spaceID: UUID,
        prefix: String = productionPrefix
    ) -> String {
        "\(service(for: spaceID, prefix: prefix))-extras"
    }
}
