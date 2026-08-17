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
                extensionID: BrowserExtensionUnpackedIdentityPolicy.extensionID(
                    for: sourceURL,
                    fileManager: fileManager
                ),
                format: format,
                archiveData: selectedData,
                sha256Hex: Data(SHA256.hash(data: selectedData)).hexString
            )
        }

        let webExtension = try await inspect(package)
        let resolvedPackage = try packageWithManifestIdentity(
            package,
            manifest: webExtension.manifest
        )
        return BrowserLocalExtensionCandidate(
            package: resolvedPackage,
            displayName: webExtension.displayName
                ?? sourceURL.deletingPathExtension().lastPathComponent,
            version: webExtension.displayVersion ?? webExtension.version,
            displayDescription: webExtension.displayDescription,
            requestedPermissions: webExtension.requestedPermissions
                .map(\.rawValue)
                .sorted(),
            requestedHosts: webExtension.allRequestedMatchPatterns
                .map(\.string)
                .sorted(),
            errors: webExtension.errors
                .map(\.localizedDescription)
                .sorted(),
            iconPayload: BrowserExtensionIconPayloadFactory.production.payload(
                for: pngData(
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

    private func packageWithManifestIdentity(
        _ package: BrowserLocalExtensionPackage,
        manifest: [String: Any]
    ) throws -> BrowserLocalExtensionPackage {
        guard package.format == .firefoxXPI,
            let declaredIdentity = declaredFirefoxIdentity(in: manifest)
        else {
            return package
        }
        guard let extensionID = BrowserMozillaExtensionID(declaredIdentity)
        else {
            throw BrowserLocalExtensionProviderError.invalidFirefoxIdentity
        }
        return BrowserLocalExtensionPackage(
            extensionID: extensionID.rawValue,
            format: package.format,
            archiveData: package.archiveData,
            sha256Hex: package.sha256Hex
        )
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
