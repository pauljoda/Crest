import AppKit
import Foundation
import Security
import WebKit

@MainActor
struct BrowserSafariWebExtensionInspector {
    private let locator: BrowserSafariWebExtensionAppLocator

    init(
        locator: BrowserSafariWebExtensionAppLocator =
            BrowserSafariWebExtensionAppLocator()
    ) {
        self.locator = locator
    }

    func inspect(
        applicationURL: URL
    ) async throws -> [BrowserSafariWebExtensionCandidate] {
        let descriptors = try locator.locate(in: applicationURL)
        let applicationName =
            descriptors.first?.applicationDisplayName
            ?? applicationURL.deletingPathExtension().lastPathComponent
        guard !descriptors.isEmpty else {
            throw
                BrowserSafariWebExtensionInspectorError
                .noWebExtensions(applicationName: applicationName)
        }
        try validateSignature(
            at: applicationURL,
            itemName: applicationName
        )
        let bookmark = try applicationURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var candidates: [BrowserSafariWebExtensionCandidate] = []
        candidates.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            try validateSignature(
                at: descriptor.extensionBundleURL,
                itemName: descriptor.displayName
            )
            guard let bundle = Bundle(url: descriptor.extensionBundleURL) else {
                throw BrowserSafariWebExtensionInspectorError
                    .missingExtensionBundle
            }
            let webExtension = try await WKWebExtension(
                appExtensionBundle: bundle
            )
            let teamIdentifier = try signingTeamIdentifier(
                at: descriptor.extensionBundleURL
            )
            candidates.append(
                BrowserSafariWebExtensionCandidate(
                    source: BrowserSafariWebExtensionSource(
                        applicationBookmark: bookmark,
                        applicationBundleIdentifier:
                            descriptor.applicationBundleIdentifier,
                        extensionBundleIdentifier:
                            descriptor.extensionBundleIdentifier,
                        relativeBundlePath: descriptor.relativeBundlePath,
                        developerTeamIdentifier: teamIdentifier
                    ),
                    applicationDisplayName:
                        descriptor.applicationDisplayName,
                    displayName: webExtension.displayName
                        ?? descriptor.displayName,
                    version: webExtension.displayVersion
                        ?? webExtension.version
                        ?? descriptor.version,
                    displayDescription: webExtension.displayDescription,
                    requestedPermissions: webExtension.requestedPermissions
                        .map(\.rawValue)
                        .sorted(),
                    requestedHosts:
                        webExtension.allRequestedMatchPatterns
                        .map(\.string)
                        .sorted(),
                    errors: BrowserWebExtensionManifestCompatibilityPolicy
                        .displayErrors(for: webExtension),
                    iconPayload: BrowserExtensionIconPayloadFactory.production
                        .payload(
                            for: pngData(
                                for: webExtension.icon(
                                    for: CGSize(width: 64, height: 64)
                                )
                            )
                        ),
                    hasOptionsPage: webExtension.hasOptionsPage,
                    hasCommands: webExtension.hasCommands,
                    hasContentModificationRules:
                        webExtension.hasContentModificationRules
                )
            )
        }
        return candidates
    }

    private func validateSignature(
        at url: URL,
        itemName: String
    ) throws {
        let code = try staticCode(at: url)
        let flags = SecCSFlags(
            rawValue: UInt32(
                kSecCSCheckAllArchitectures | kSecCSStrictValidate
            )
        )
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw
                BrowserSafariWebExtensionInspectorError
                .invalidCodeSignature(itemName: itemName)
        }
    }

    private func signingTeamIdentifier(at url: URL) throws -> String? {
        let code = try staticCode(at: url)
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &information
        )
        guard status == errSecSuccess,
            let values = information as? [CFString: Any]
        else {
            return nil
        }
        return values[kSecCodeInfoTeamIdentifier] as? String
    }

    private func staticCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(
            url as CFURL,
            SecCSFlags(),
            &code
        )
        guard status == errSecSuccess, let code else {
            throw
                BrowserSafariWebExtensionInspectorError
                .invalidCodeSignature(itemName: url.lastPathComponent)
        }
        return code
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
