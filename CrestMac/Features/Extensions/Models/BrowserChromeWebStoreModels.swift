import AppKit
import Foundation
import WebKit

struct BrowserChromeWebStoreCandidate: Identifiable, Sendable {
    let item: BrowserChromeWebStoreItem
    let source: BrowserChromeWebStoreSource
    let verifiedPackage: BrowserVerifiedCRX3Package
    let displayName: String
    let version: String?
    let displayDescription: String?
    let requestedPermissions: [String]
    let requestedHosts: [String]
    let errors: [String]
    let iconPayload: BrowserExtensionIconPayload?
    let hasOptionsPage: Bool
    let hasCommands: Bool
    let hasContentModificationRules: Bool
    let nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    let iCloudPasswordsCapability: BrowserICloudPasswordsCapability

    var id: String { source.extensionID.rawValue }
    var iconData: Data? { iconPayload?.data }

    var compatibility: BrowserExtensionCompatibilityAssessment {
        BrowserExtensionCompatibilityPolicy.assess(
            extensionID: source.extensionID.rawValue,
            requestedPermissions: requestedPermissions,
            source: .chromeWebStore,
            nativeMessagingCapability: nativeMessagingCapability,
            iCloudPasswordsCapability: iCloudPasswordsCapability
        )
    }
}

enum BrowserWebExtensionCompatibilityPackageError: LocalizedError {
    case invalidBackgroundManifest
    case unsafeBackgroundPath
    case archiveExpansionFailed

    var errorDescription: String? {
        switch self {
        case .invalidBackgroundManifest:
            "Crest couldn’t prepare this extension’s WebKit compatibility layer."
        case .unsafeBackgroundPath:
            "The extension declared an unsafe background script path."
        case .archiveExpansionFailed:
            "Crest couldn’t unpack this extension for WebKit compatibility."
        }
    }
}

final class BrowserWebExtensionPreparedPackage {
    let resourceURL: URL

    private let rootURL: URL
    private let fileManager: FileManager

    init(
        resourceURL: URL,
        rootURL: URL,
        fileManager: FileManager
    ) {
        self.resourceURL = resourceURL
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    deinit {
        try? fileManager.removeItem(at: rootURL)
    }
}

enum BrowserChromeWebStoreProviderError: LocalizedError {
    case invalidResponse
    case packageTooLarge
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The Chrome Web Store did not return an extension package."
        case .packageTooLarge:
            "The extension package exceeds Crest’s safe import limits."
        case .transport(let error):
            "The Chrome Web Store download failed: \(error.localizedDescription)"
        }
    }
}

enum BrowserChromeWebStoreUpdaterError: LocalizedError {
    case unavailableRuntime
    case missingSpace
    case missingInstallation
    case unverifiableSource
    case identityMismatch

    var errorDescription: String? {
        switch self {
        case .unavailableRuntime:
            "Crest’s extension runtime is no longer available."
        case .missingSpace:
            "The Space that installed this extension is no longer open."
        case .missingInstallation:
            "This extension is no longer installed in that Space."
        case .unverifiableSource:
            "Crest cannot confirm which Chrome Web Store page installed this extension."
        case .identityMismatch:
            "The Chrome Web Store returned a package for a different extension."
        }
    }
}
