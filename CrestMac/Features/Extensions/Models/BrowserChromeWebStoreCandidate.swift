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
