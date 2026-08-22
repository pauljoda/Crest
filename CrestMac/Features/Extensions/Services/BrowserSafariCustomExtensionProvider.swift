import AppKit
import Foundation
import WebKit

enum BrowserSafariCustomExtensionProviderError: LocalizedError {
    case invalidSnapshot

    var errorDescription: String? {
        String(
            localized:
                "Safari’s custom extension files could not be safely inspected."
        )
    }
}

@MainActor
struct BrowserSafariCustomExtensionProvider {
    private let fileManager: FileManager
    private let nativeMessagingCapability: BrowserExtensionNativeMessagingCapability

    init(
        fileManager: FileManager = .default,
        nativeMessagingCapability:
            BrowserExtensionNativeMessagingCapability =
            BrowserPlatformExtensionNativeMessagingCapability.currentBuild
    ) {
        self.fileManager = fileManager
        self.nativeMessagingCapability = nativeMessagingCapability
    }

    func candidate(
        for package: BrowserLocalExtensionPackage
    ) async throws -> BrowserLocalExtensionCandidate {
        guard let files = package.validatedSafariCustomDirectoryFiles
        else {
            throw BrowserSafariCustomExtensionProviderError.invalidSnapshot
        }

        let temporaryURL = fileManager.temporaryDirectory.appending(
            path:
                "crest-safari-custom-inspection-"
                + UUID().uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try fileManager.createDirectory(
            at: temporaryURL,
            withIntermediateDirectories: true
        )
        for file in files {
            let fileURL = temporaryURL.appending(path: file.relativePath)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.data.write(to: fileURL, options: [.atomic])
        }

        let webExtension = try await WKWebExtension(
            resourceBaseURL: temporaryURL
        )
        return BrowserLocalExtensionCandidate(
            package: package,
            displayName: webExtension.displayName
                ?? String(localized: "Safari Custom Extension"),
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
