import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserChromeWebStoreProvider {
    typealias Download = @MainActor (URL) async throws -> (Data, URLResponse)

    private let download: Download
    private let verifier: BrowserCRX3Verifier
    private let fileManager: FileManager
    private let nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    private let iCloudPasswordsCapability: BrowserICloudPasswordsCapability

    init(
        verifier: BrowserCRX3Verifier = BrowserCRX3Verifier(),
        fileManager: FileManager = .default,
        nativeMessagingCapability:
            BrowserExtensionNativeMessagingCapability =
            BrowserPlatformExtensionNativeMessagingCapability.currentBuild,
        iCloudPasswordsCapability:
            BrowserICloudPasswordsCapability = .currentBuild,
        download: @escaping Download = { url in
            try await URLSession.shared.data(from: url)
        }
    ) {
        self.verifier = verifier
        self.fileManager = fileManager
        self.nativeMessagingCapability = nativeMessagingCapability
        self.iCloudPasswordsCapability = iCloudPasswordsCapability
        self.download = download
    }

    func candidate(
        for item: BrowserChromeWebStoreItem
    ) async throws -> BrowserChromeWebStoreCandidate {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await download(
                BrowserChromeWebStoreUpdateRequest.url(for: item.id)
            )
        } catch {
            throw BrowserChromeWebStoreProviderError.transport(error)
        }
        guard data.count <= BrowserCRX3Verifier.maximumPackageByteCount else {
            throw BrowserChromeWebStoreProviderError.packageTooLarge
        }
        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            httpResponse.url?.scheme?.lowercased() == "https"
        else {
            throw BrowserChromeWebStoreProviderError.invalidResponse
        }
        let verified = try verifier.verify(data, expectedID: item.id)
        let webExtension = try await inspect(verified)
        return BrowserChromeWebStoreCandidate(
            item: item,
            source: BrowserChromeWebStoreSource(
                extensionID: item.id,
                storeURL: item.storeURL,
                crxSHA256Hex: verified.crxSHA256Hex,
                publisherKeyHashHex: verified.publisherKeyHashHex
            ),
            verifiedPackage: verified,
            displayName: webExtension.displayName ?? item.slug,
            version: webExtension.displayVersion ?? webExtension.version,
            displayDescription: webExtension.displayDescription,
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
            hasContentModificationRules:
                webExtension.hasContentModificationRules,
            nativeMessagingCapability: nativeMessagingCapability,
            iCloudPasswordsCapability: iCloudPasswordsCapability
        )
    }

    private func inspect(
        _ package: BrowserVerifiedCRX3Package
    ) async throws -> WKWebExtension {
        let temporaryURL = fileManager.temporaryDirectory.appending(
            path: "crest-chrome-extension-inspection-\(UUID().uuidString.lowercased()).zip"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try package.zipArchiveData.write(to: temporaryURL, options: [.atomic])
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
