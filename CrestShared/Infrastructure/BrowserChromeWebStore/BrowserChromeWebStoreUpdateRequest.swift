import Foundation

enum BrowserChromeWebStoreUpdateRequest {
    /// The Chrome build Crest presents to Google's extension endpoint.
    ///
    /// The store uses this to decide which package a client is eligible for,
    /// so it tracks current Chrome stable rather than Crest's own version.
    static let productVersion = "152.0.0.0"

    /// The download endpoint: a redirect straight to the signed CRX3.
    static func url(for extensionID: BrowserChromeExtensionID) -> URL {
        endpoint(
            response: "redirect",
            extensionID: extensionID,
            installedVersion: nil
        )
    }

    /// The version-probe endpoint.
    ///
    /// Google answers with an Omaha XML document rather than a package, which
    /// lets Crest learn the current published version for a few hundred bytes
    /// instead of a multi-megabyte download.
    ///
    /// `installedVersion` is intentionally left out by default. Sending it
    /// makes the store collapse an up-to-date answer to a bare `noupdate`,
    /// which hides the published version Crest wants to show and compare
    /// locally. Omitting it always returns the current version, and Crest
    /// decides for itself whether that is an upgrade.
    static func updateCheckURL(
        for extensionID: BrowserChromeExtensionID,
        installedVersion: String? = nil
    ) -> URL {
        endpoint(
            response: "updatecheck",
            extensionID: extensionID,
            installedVersion: installedVersion
        )
    }

    private static func endpoint(
        response: String,
        extensionID: BrowserChromeExtensionID,
        installedVersion: String?
    ) -> URL {
        var applicationParameters = "id=\(extensionID.rawValue)"
        if let installedVersion, !installedVersion.isEmpty {
            applicationParameters += "&v=\(installedVersion)"
        }
        applicationParameters += "&uc"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "clients2.google.com"
        components.path = "/service/update2/crx"
        components.queryItems = [
            URLQueryItem(name: "response", value: response),
            URLQueryItem(name: "prodversion", value: productVersion),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: applicationParameters),
        ]
        guard let url = components.url else {
            preconditionFailure("The fixed Chrome Web Store update endpoint is invalid.")
        }
        return url
    }
}
