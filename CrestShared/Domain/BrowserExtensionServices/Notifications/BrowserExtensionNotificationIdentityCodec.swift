import Foundation

/// Reversible encoding between a notification identity and the flat string
/// identifiers the host notification center stores.
///
/// Extension-authored notification identifiers are arbitrary strings chosen by
/// untrusted JavaScript, so a plain delimiter is not decodable: an extension
/// could embed the delimiter and impersonate another client's notification.
/// The client identifier is therefore length-prefixed in UTF-8 bytes, which
/// makes the split point independent of both identifiers' contents.
enum BrowserExtensionNotificationIdentityCodec {
    /// Namespace shared by every identifier this codec produces.
    static let prefix = "crest.webextension.notification"

    /// Namespace for the per-notification category that carries button actions.
    static let categoryPrefix = "crest.webextension.notification-category"

    /// The system-wide unique identifier for a delivered notification.
    static func systemIdentifier(
        for identity: BrowserExtensionNotificationIdentity
    ) -> String {
        encoded(prefix: prefix, identity: identity)
    }

    /// The category identifier that carries `identity`'s button actions.
    static func categoryIdentifier(
        for identity: BrowserExtensionNotificationIdentity
    ) -> String {
        encoded(prefix: categoryPrefix, identity: identity)
    }

    /// Groups every notification from one extension into a single thread so the
    /// host can collapse them the way it collapses any other app's group.
    static func threadIdentifier(
        for client: BrowserExtensionServiceClientID
    ) -> String {
        "\(prefix).thread.\(client.rawValue)"
    }

    /// Recovers the identity from a system identifier, or `nil` when the
    /// identifier was not produced by ``systemIdentifier(for:)``.
    static func identity(
        fromSystemIdentifier systemIdentifier: String
    ) -> BrowserExtensionNotificationIdentity? {
        decoded(prefix: prefix, identifier: systemIdentifier)
    }

    /// Recovers the identity from a category identifier, or `nil` when the
    /// identifier was not produced by ``categoryIdentifier(for:)``.
    static func identity(
        fromCategoryIdentifier categoryIdentifier: String
    ) -> BrowserExtensionNotificationIdentity? {
        decoded(prefix: categoryPrefix, identifier: categoryIdentifier)
    }

    private static func encoded(
        prefix: String,
        identity: BrowserExtensionNotificationIdentity
    ) -> String {
        let client = identity.client.rawValue
        return """
            \(prefix).\(client.utf8.count).\(client).\
            \(identity.notificationIdentifier)
            """
    }

    private static func decoded(
        prefix: String,
        identifier: String
    ) -> BrowserExtensionNotificationIdentity? {
        let namespace = "\(prefix)."
        guard identifier.hasPrefix(namespace) else { return nil }

        let lengthStart = identifier.index(
            identifier.startIndex,
            offsetBy: namespace.count
        )
        guard
            let lengthEnd = identifier[lengthStart...].firstIndex(of: "."),
            let clientByteCount = Int(identifier[lengthStart..<lengthEnd]),
            clientByteCount > 0
        else {
            return nil
        }

        let clientStart = identifier.index(after: lengthEnd)
        let remainder = Array(identifier[clientStart...].utf8)
        guard remainder.count > clientByteCount,
            remainder[clientByteCount] == UInt8(ascii: "."),
            let client = String(bytes: remainder[..<clientByteCount], encoding: .utf8),
            let clientID = BrowserExtensionServiceClientID(client),
            let notificationIdentifier = String(
                bytes: remainder[(clientByteCount + 1)...],
                encoding: .utf8
            )
        else {
            return nil
        }

        return BrowserExtensionNotificationIdentity(
            client: clientID,
            notificationIdentifier: notificationIdentifier
        )
    }
}
