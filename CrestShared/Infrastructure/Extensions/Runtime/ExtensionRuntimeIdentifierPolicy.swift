import CryptoKit
import Foundation

struct BrowserExtensionRuntimeIdentity: Equatable, Sendable {
    let extensionID: String
    let uniqueIdentifier: String
    let baseURL: URL
    let referenceEnvironment: BrowserExtensionReferenceEnvironment

    init(
        extensionID: String,
        uniqueIdentifier: String,
        baseURL: URL,
        referenceEnvironment: BrowserExtensionReferenceEnvironment = .webKit
    ) {
        self.extensionID = extensionID
        self.uniqueIdentifier = uniqueIdentifier
        self.baseURL = baseURL
        self.referenceEnvironment = referenceEnvironment
    }
}

enum BrowserExtensionRuntimeIdentifierPolicy {
    // Preserve the origin class Chrome Web Store packages are authored for.
    // WebKit accepts any custom base-URL scheme, but cross-origin extension
    // requests are classified by their initiating scheme before host access
    // is applied. A branded scheme makes an otherwise reviewed extension look
    // like ordinary custom-scheme content at that boundary.
    static let urlScheme = "chrome-extension"

    /// The origin and unique identifier a loaded package runs under.
    ///
    /// A verified Chrome Web Store package runs on the origin Chrome gives it:
    /// `chrome-extension://<store id>/`. That origin is not cosmetic. The rest
    /// of the web already knows the package by it, and several things a real
    /// Chrome extension depends on are decided by string-comparing it:
    /// an embedder's `frame-ancestors` list and the `ancestorOrigins` check an
    /// embedded surface runs in JavaScript, a service's CORS exemption for its
    /// own extension, a web-accessible-resource probe, and any redirect back
    /// to `chrome-extension://<id>/…`. A synthetic host fails all of them
    /// silently, and no permission or manifest edit can compensate.
    ///
    /// Every other source keeps a per-Space host derived from
    /// `sha256(<id>.space.<space uuid>)`. Those packages have no public origin
    /// to preserve, and the hash keeps two Spaces from ever meeting.
    ///
    /// Sharing one origin across Spaces is safe here because Spaces do not
    /// share WebKit storage. Every Space owns a `BrowsingProfile`
    /// (`BrowserSession.makeBlankSpace` mints a fresh one and
    /// `repairRuntimeIntegrity` reidentifies any duplicate), and
    /// `BrowserExtensionRuntimeContextController.controller(for:)` builds each
    /// Space's controller on `WKWebsiteDataStore(forIdentifier: profile.id)`.
    /// Service-worker registrations — the reason this host was ever hashed —
    /// live in that per-Space store, so one Space cannot reuse another's
    /// dormant registration and lose its runtime listeners.
    ///
    /// `sharesDataStoreWithAnotherContext` is the escape hatch for the day
    /// that stops being true: pass it when another Space already runs this
    /// package on the same data store, and the package falls back to the
    /// hashed per-Space host rather than colliding on a registration. The
    /// caller decides, because only the controller can see the other Spaces.
    static func identity(
        extensionID: String,
        source: BrowserExtensionInstallationSource?,
        spaceID: SpaceID,
        sharesDataStoreWithAnotherContext: Bool = false
    ) -> BrowserExtensionRuntimeIdentity {
        let uniqueIdentifier = identifier(
            extensionID: extensionID,
            source: source,
            spaceID: spaceID
        )
        return BrowserExtensionRuntimeIdentity(
            extensionID: extensionID,
            uniqueIdentifier: uniqueIdentifier,
            baseURL: baseURL(
                extensionID: extensionID,
                source: source,
                spaceID: spaceID,
                sharesDataStoreWithAnotherContext:
                    sharesDataStoreWithAnotherContext
            ),
            referenceEnvironment: referenceEnvironment(for: source)
        )
    }

    private static func baseURL(
        extensionID: String,
        source: BrowserExtensionInstallationSource?,
        spaceID: SpaceID,
        sharesDataStoreWithAnotherContext: Bool
    ) -> URL {
        if case .chromeWebStore(let chromeSource) = source,
            chromeSource.extensionID.rawValue == extensionID,
            !sharesDataStoreWithAnotherContext
        {
            return url(host: extensionID.lowercased())
        }
        let originIdentifier =
            "\(extensionID).space.\(spaceID.rawValue.uuidString.lowercased())"
        let digest = SHA256.hash(data: Data(originIdentifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return url(host: "extension-\(digest)")
    }

    private static func url(host: String) -> URL {
        guard let url = URL(string: "\(urlScheme)://\(host)/") else {
            preconditionFailure("Unable to construct extension runtime URL")
        }
        return url
    }

    private static func referenceEnvironment(
        for source: BrowserExtensionInstallationSource?
    ) -> BrowserExtensionReferenceEnvironment {
        switch source {
        case .chromeWebStore:
            .chromium
        case .mozillaAddons:
            .firefox
        case .safariWebExtension:
            .webKit
        case .localPackage, .unpackedPackage, nil:
            .webKit
        }
    }

    static func identifier(
        extensionID: String,
        source: BrowserExtensionInstallationSource?,
        spaceID: SpaceID
    ) -> String {
        if case .chromeWebStore(let chromeSource) = source,
            chromeSource.extensionID.rawValue == extensionID
        {
            return extensionID
        }
        return "\(extensionID).space.\(spaceID.rawValue.uuidString.lowercased())"
    }
}
