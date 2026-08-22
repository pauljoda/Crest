import AppKit
import Foundation
import WebKit

/// Turns an addons.mozilla.org detail page into a verified, inspected install
/// candidate.
///
/// The listing is fetched first because it is what makes the package
/// verifiable: AMO publishes the gecko identity, the exact download URL, its
/// byte count, and its SHA-256 digest. Every one of those is then required to
/// hold for the bytes that actually arrive, and the add-on's own manifest is
/// required to agree about who it is.
@MainActor
final class BrowserMozillaAddonsProvider {
    typealias Download = @MainActor (URL) async throws -> (Data, URLResponse)

    private let download: Download
    private let verifier: BrowserXPIVerifier
    private let fileManager: FileManager
    private let nativeMessagingCapability: BrowserExtensionNativeMessagingCapability

    init(
        verifier: BrowserXPIVerifier = BrowserXPIVerifier(),
        fileManager: FileManager = .default,
        nativeMessagingCapability:
            BrowserExtensionNativeMessagingCapability =
            BrowserPlatformExtensionNativeMessagingCapability.currentBuild,
        download: @escaping Download = { url in
            try await URLSession.shared.data(from: url)
        }
    ) {
        self.verifier = verifier
        self.fileManager = fileManager
        self.nativeMessagingCapability = nativeMessagingCapability
        self.download = download
    }

    func candidate(
        for item: BrowserMozillaAddonsItem
    ) async throws -> BrowserMozillaAddonsCandidate {
        let listing = try await listing(for: item)
        let verified = try await verifiedPackage(for: listing)
        let webExtension = try await inspect(verified)
        try crossCheckDeclaredIdentity(
            of: webExtension,
            against: listing.extensionID
        )
        return BrowserMozillaAddonsCandidate(
            item: item,
            source: BrowserMozillaAddonsSource(
                slug: listing.slug,
                extensionID: listing.extensionID,
                storeURL: item.storeURL,
                version: listing.version,
                xpiSHA256Hex: verified.xpiSHA256Hex
            ),
            verifiedPackage: verified,
            displayName: webExtension.displayName ?? listing.displayName,
            version: webExtension.displayVersion ?? listing.version,
            displayDescription: webExtension.displayDescription
                ?? listing.summary,
            requestedPermissions: webExtension.requestedPermissions
                .map(\.rawValue)
                .sorted(),
            requestedHosts: webExtension.allRequestedMatchPatterns
                .map(\.string)
                .sorted(),
            errors: BrowserWebExtensionManifestCompatibilityPolicy
                .displayErrors(for: webExtension),
            iconPayload: BrowserExtensionIconPayloadFactory.production
                .payload(
                    for: pngData(
                        for: webExtension.icon(
                            for: CGSize(width: 96, height: 96)
                        )
                    )
                ),
            hasOptionsPage: webExtension.hasOptionsPage,
            hasCommands: webExtension.hasCommands,
            isMozillaRecommended: listing.isMozillaRecommended,
            nativeMessagingCapability: nativeMessagingCapability
        )
    }

    private func listing(
        for item: BrowserMozillaAddonsItem
    ) async throws -> BrowserMozillaAddonsListing {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await download(
                BrowserMozillaAddonsListingRequest.url(for: item.slug)
            )
        } catch {
            throw BrowserMozillaAddonsProviderError.transport(error)
        }
        guard let httpResponse = response as? HTTPURLResponse,
            isTrusted(httpResponse.url)
        else {
            throw BrowserMozillaAddonsProviderError.invalidListingResponse
        }
        guard httpResponse.statusCode != 404 else {
            throw BrowserMozillaAddonsProviderError.addonNotFound
        }
        guard httpResponse.statusCode == 200 else {
            throw BrowserMozillaAddonsProviderError.invalidListingResponse
        }
        let listing = try BrowserMozillaAddonsListingDecoder.listing(from: data)
        guard listing.slug == item.slug else {
            throw BrowserMozillaAddonsProviderError.listingIdentityMismatch
        }
        return listing
    }

    private func verifiedPackage(
        for listing: BrowserMozillaAddonsListing
    ) async throws -> BrowserVerifiedXPIPackage {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await download(listing.downloadURL)
        } catch {
            throw BrowserMozillaAddonsProviderError.transport(error)
        }
        guard data.count <= BrowserXPIVerifier.maximumPackageByteCount else {
            throw BrowserMozillaAddonsProviderError.packageTooLarge
        }
        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw BrowserMozillaAddonsProviderError.invalidPackageResponse
        }
        // A redirect chain may not leave Mozilla: the digest below only proves
        // the bytes match what some host claimed, so the host still matters.
        guard isTrusted(httpResponse.url) else {
            throw BrowserMozillaAddonsProviderError.untrustedDownloadHost
        }
        return try verifier.verify(
            data,
            expectedSHA256Hex: listing.xpiSHA256Hex,
            expectedByteCount: listing.byteCount,
            extensionID: listing.extensionID
        )
    }

    private func isTrusted(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https"
            && url?.host?.lowercased() == BrowserMozillaAddonsListingRequest.host
    }

    /// Rejects a package whose own manifest claims a gecko identity other than
    /// the one its listing published.
    ///
    /// A gecko ID is optional in `manifest.json` — AMO assigns one at signing
    /// when the author omits it — so an absent declaration is normal and the
    /// listing's identity stands.
    private func crossCheckDeclaredIdentity(
        of webExtension: WKWebExtension,
        against extensionID: BrowserMozillaExtensionID
    ) throws {
        guard let declared = Self.declaredGeckoID(in: webExtension.manifest)
        else {
            return
        }
        guard declared == extensionID else {
            throw BrowserMozillaAddonsProviderError.extensionIdentityMismatch
        }
    }

    private static func declaredGeckoID(
        in manifest: [String: Any]
    ) -> BrowserMozillaExtensionID? {
        let settings =
            manifest["browser_specific_settings"] as? [String: Any]
            ?? manifest["applications"] as? [String: Any]
        guard let gecko = settings?["gecko"] as? [String: Any],
            let identifier = gecko["id"] as? String
        else {
            return nil
        }
        return BrowserMozillaExtensionID(identifier)
    }

    private func inspect(
        _ package: BrowserVerifiedXPIPackage
    ) async throws -> WKWebExtension {
        let temporaryURL = fileManager.temporaryDirectory.appending(
            path: "crest-mozilla-addon-inspection-\(UUID().uuidString.lowercased()).zip"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try package.archiveData.write(to: temporaryURL, options: [.atomic])
        return try await WKWebExtension(resourceBaseURL: temporaryURL)
    }

    private func pngData(for image: NSImage?) -> Data? {
        guard let tiffData = image?.tiffRepresentation,
            let representation = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return representation.representation(
            using: .png,
            properties: [:]
        )
    }
}
