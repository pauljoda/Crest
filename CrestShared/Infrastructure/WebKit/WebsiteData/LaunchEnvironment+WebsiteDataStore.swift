import CryptoKit
import Foundation

/// Which persistent WebKit website data store each profile opens in a launch.
extension BrowserLaunchEnvironment {
    // MARK: - Static Variables

    /// The namespace every named isolated launch derives its own from
    /// (04d9f602-9135-4933-88bf-bdb62c7d619d). It is frozen: a different value
    /// would leave every review's existing stores behind.
    private static let isolatedWebsiteDataStores = UUID(
        uuid: (
            0x04, 0xd9, 0xf6, 0x02, 0x91, 0x35, 0x49, 0x33,
            0x88, 0xbf, 0xbd, 0xb6, 0x2c, 0x7d, 0x61, 0x9d
        ))

    // MARK: - Actions - Website data

    /// The identifier of the persistent WebKit store `profileID` opens.
    ///
    /// Every launch except a named isolated one opens the profile's own store.
    /// A named isolated launch derives its store from its isolation ID and the
    /// profile ID. WebKit keeps identified stores per bundle, and a review that
    /// opens a copy of the installed session carries the installed profile IDs.
    /// Without this, a review signed as the installed app would share the
    /// person's cookies and site storage, and clearing site data or deleting a
    /// Space there would erase them. Relaunching with the same isolation ID
    /// finds the same stores again.
    func websiteDataStoreIdentifier(forProfileID profileID: UUID) -> UUID {
        guard requiresIsolation, let persistentIsolationID else { return profileID }
        let isolation = UUID(name: Data(persistentIsolationID.utf8), namespace: Self.isolatedWebsiteDataStores)
        return UUID(name: Data(profileID.uuidString.lowercased().utf8), namespace: isolation)
    }
}

extension UUID {
    /// The name-based (version 5) UUID for `name` in `namespace`, as RFC 9562
    /// section 5.5 defines it.
    fileprivate init(name: Data, namespace: UUID) {
        var input = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        input.append(name)
        var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        self.init(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
