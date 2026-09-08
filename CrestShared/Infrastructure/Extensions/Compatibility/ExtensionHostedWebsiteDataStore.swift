import CryptoKit
import Foundation
import WebKit

/// Storage for extension-hosted websites. Its cookie jar can support embedded
/// sign-in without changing the cookie policy of ordinary browser tabs.
@MainActor
enum BrowserExtensionHostedWebsiteDataStore {
    static func identifier(forProfileID profileID: UUID) -> UUID {
        let digest = Array(
            SHA256.hash(data: Data("crest.extension-hosted-storage.\(profileID.uuidString.lowercased())".utf8)))
        return UUID(
            uuid: (
                digest[0], digest[1], digest[2], digest[3], digest[4], digest[5],
                (digest[6] & 0x0f) | 0x50, digest[7], (digest[8] & 0x3f) | 0x80, digest[9],
                digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
            ))
    }

    static func make(for normalStore: WKWebsiteDataStore, spaceID: SpaceID) -> WKWebsiteDataStore {
        guard normalStore.isPersistent else { return .nonPersistent() }
        return WKWebsiteDataStore(forIdentifier: identifier(forProfileID: normalStore.identifier ?? spaceID.rawValue))
    }

    /// WebKit relates extension configurations to their background view. Views
    /// with different stores cannot share that relationship; native runtime IPC
    /// continues through the retained extension controller.
    static func apply(_ dataStore: WKWebsiteDataStore, to configuration: WKWebViewConfiguration) -> Bool {
        let selector = NSSelectorFromString("_setRelatedWebView:")
        guard configuration.responds(to: selector) else { return false }
        configuration.perform(selector, with: nil)
        configuration.websiteDataStore = dataStore
        return true
    }
}
