import Foundation
import Security
import WebKit

@MainActor
struct BrowserSafariWebExtensionResource {
    let webExtension: WKWebExtension
    let access: BrowserSecurityScopedResourceAccess

    init(source: BrowserSafariWebExtensionSource) async throws {
        let access = try BrowserSecurityScopedResourceAccess(
            bookmark: source.applicationBookmark
        )
        let applicationURL = access.url.standardizedFileURL
        guard
            Bundle(url: applicationURL)?.bundleIdentifier
                == source.applicationBundleIdentifier
        else {
            throw BrowserSafariWebExtensionResourceError.hostAppChanged
        }

        let extensionURL =
            applicationURL
            .appendingPathComponent(source.relativeBundlePath)
            .standardizedFileURL
        let appPrefix =
            applicationURL.path.hasSuffix("/")
            ? applicationURL.path
            : applicationURL.path + "/"
        guard extensionURL.path.hasPrefix(appPrefix),
            extensionURL.pathExtension.lowercased() == "appex",
            let bundle = Bundle(url: extensionURL),
            bundle.bundleIdentifier == source.extensionBundleIdentifier
        else {
            throw BrowserSafariWebExtensionResourceError.extensionMoved
        }
        try Self.validateSignature(at: extensionURL)
        if let expectedTeam = source.developerTeamIdentifier {
            guard try Self.teamIdentifier(at: extensionURL) == expectedTeam else {
                throw BrowserSafariWebExtensionResourceError.signerChanged
            }
        }

        webExtension = try await WKWebExtension(
            appExtensionBundle: bundle
        )
        self.access = access
    }

    private static func validateSignature(at url: URL) throws {
        let code = try staticCode(at: url)
        let flags = SecCSFlags(
            rawValue: UInt32(
                kSecCSCheckAllArchitectures | kSecCSStrictValidate
            )
        )
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw BrowserSafariWebExtensionResourceError.invalidSignature
        }
    }

    private static func teamIdentifier(at url: URL) throws -> String? {
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

    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(
            url as CFURL,
            SecCSFlags(),
            &code
        )
        guard status == errSecSuccess, let code else {
            throw BrowserSafariWebExtensionResourceError.invalidSignature
        }
        return code
    }
}
