import AppKit
import CryptoKit
import Foundation
import WebKit

@MainActor
final class BrowserLocalExtensionProvider {
    private let fileManager: FileManager
    private let crxVerifier: BrowserCRX3Verifier
    private let nativeMessagingCapability: BrowserExtensionNativeMessagingCapability

    init(
        fileManager: FileManager = .default,
        crxVerifier: BrowserCRX3Verifier = BrowserCRX3Verifier(),
        nativeMessagingCapability:
            BrowserExtensionNativeMessagingCapability =
            BrowserPlatformExtensionNativeMessagingCapability.currentBuild
    ) {
        self.fileManager = fileManager
        self.crxVerifier = crxVerifier
        self.nativeMessagingCapability = nativeMessagingCapability
    }

    func candidate(
        for sourceURL: URL
    ) async throws -> BrowserLocalExtensionCandidate {
        let format = try format(for: sourceURL)
        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isSymbolicLink != true else {
            throw BrowserLocalExtensionProviderError.symbolicLink
        }
        guard values.isRegularFile == true else {
            throw BrowserLocalExtensionProviderError.invalidArchive
        }
        guard
            values.fileSize ?? 0
                <= BrowserCRX3Verifier.maximumPackageByteCount
        else {
            throw BrowserLocalExtensionProviderError.packageTooLarge
        }

        let selectedData = try Data(
            contentsOf: sourceURL,
            options: [.mappedIfSafe]
        )
        let package: BrowserLocalExtensionPackage
        switch format {
        case .chromeCRX3:
            let verified = try crxVerifier.verify(selectedData)
            package = BrowserLocalExtensionPackage(
                extensionID: verified.extensionID.rawValue,
                format: format,
                archiveData: verified.zipArchiveData,
                sha256Hex: Data(
                    SHA256.hash(data: verified.zipArchiveData)
                ).hexString
            )
        case .firefoxXPI:
            guard selectedData.starts(with: [0x50, 0x4b, 0x03, 0x04]) else {
                throw BrowserLocalExtensionProviderError.invalidArchive
            }
            package = BrowserLocalExtensionPackage(
                extensionID: "local.xpi." + UUID().uuidString.lowercased(),
                format: format,
                archiveData: selectedData,
                sha256Hex: Data(SHA256.hash(data: selectedData)).hexString
            )
        case .safariCustom:
            throw BrowserLocalExtensionProviderError.unsupportedFileType
        }

        let webExtension = try await inspect(package)
        let resolvedPackage = try packageWithLocalProvenance(
            package,
            manifest: webExtension.manifest
        )
        return BrowserLocalExtensionCandidate(
            package: resolvedPackage,
            displayName: webExtension.displayName
                ?? sourceURL.deletingPathExtension().lastPathComponent,
            version: webExtension.displayVersion ?? webExtension.version,
            displayDescription: webExtension.displayDescription,
            requestedPermissions: BrowserExtensionManagedPermissionPolicy.requestedPermissions(
                native: webExtension.requestedPermissions.map(\.rawValue), manifest: webExtension.manifest),
            requestedHosts: webExtension.allRequestedMatchPatterns
                .map(\.string)
                .sorted(),
            errors:
                BrowserWebExtensionManifestCompatibilityPolicy
                .displayErrors(for: webExtension),
            iconPayload: BrowserExtensionIconPayloadFactory.production.payload(
                for: BrowserExtensionIconPNGEncoder.data(
                    for: webExtension.icon(
                        for: CGSize(width: 96, height: 96)
                    )
                )
            ),
            hasOptionsPage: webExtension.hasOptionsPage,
            hasCommands: webExtension.hasCommands,
            nativeMessagingCapability: nativeMessagingCapability
        )
    }

    private func format(
        for sourceURL: URL
    ) throws -> BrowserLocalExtensionPackageFormat {
        switch sourceURL.pathExtension.lowercased() {
        case "crx":
            .chromeCRX3
        case "xpi":
            .firefoxXPI
        default:
            throw BrowserLocalExtensionProviderError.unsupportedFileType
        }
    }

    private func inspect(
        _ package: BrowserLocalExtensionPackage
    ) async throws -> WKWebExtension {
        let temporaryURL = fileManager.temporaryDirectory.appending(
            path:
                "crest-local-extension-inspection-"
                + "\(UUID().uuidString.lowercased()).zip"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try package.archiveData.write(to: temporaryURL, options: [.atomic])
        return try await WKWebExtension(resourceBaseURL: temporaryURL)
    }

    private func packageWithLocalProvenance(
        _ package: BrowserLocalExtensionPackage,
        manifest: [String: Any]
    ) throws -> BrowserLocalExtensionPackage {
        guard package.format == .firefoxXPI else { return package }
        var resolved = package
        // The selected file identifies a local import, never a publisher.
        // Every import gets a new authority/storage lineage, including reimports
        // of the same file. The manifest remains intact for Firefox compatibility.
        resolved.storageIdentifier = UUID().uuidString.lowercased()
        if let declaredIdentity = declaredFirefoxIdentity(in: manifest) {
            guard let declaredID = BrowserMozillaExtensionID(declaredIdentity) else {
                throw BrowserLocalExtensionProviderError.invalidFirefoxIdentity
            }
            resolved.declaredGeckoID = declaredID.rawValue
        }
        return resolved
    }

    private func declaredFirefoxIdentity(
        in manifest: [String: Any]
    ) -> String? {
        let settings =
            manifest["browser_specific_settings"] as? [String: Any]
            ?? manifest["applications"] as? [String: Any]
        let gecko = settings?["gecko"] as? [String: Any]
        return gecko?["id"] as? String
    }
}
