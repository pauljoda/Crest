import AppKit
import Foundation
import WebKit

struct BrowserMozillaAddonsCandidate: Identifiable, Sendable {
    let item: BrowserMozillaAddonsItem
    let source: BrowserMozillaAddonsSource
    let verifiedPackage: BrowserVerifiedXPIPackage
    let displayName: String
    let version: String?
    let displayDescription: String?
    let requestedPermissions: [String]
    let requestedHosts: [String]
    let errors: [String]
    let iconPayload: BrowserExtensionIconPayload?
    let hasOptionsPage: Bool
    let hasCommands: Bool
    let isMozillaRecommended: Bool
    let nativeMessagingCapability: BrowserExtensionNativeMessagingCapability

    var id: String { source.extensionID.rawValue }
    var iconData: Data? { iconPayload?.data }

    var compatibility: BrowserExtensionCompatibilityAssessment {
        BrowserExtensionCompatibilityPolicy.assess(
            extensionID: source.extensionID.rawValue,
            requestedPermissions: requestedPermissions,
            source: .mozillaAddons,
            nativeMessagingCapability: nativeMessagingCapability
        )
    }
}
