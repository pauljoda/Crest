import Foundation

enum CredentialKeychainNamespace {
    static let productionPrefix = ProductIdentity.serviceNamespace

    static func service(
        for spaceID: SpaceID,
        prefix: String = productionPrefix
    ) -> String {
        "\(prefix).space.\(spaceID.rawValue.uuidString.lowercased()).credential"
    }
}
