import AppKit
import Foundation
import Security
import WebKit

struct BrowserSafariWebExtensionCandidate: Equatable, Identifiable {
    let source: BrowserSafariWebExtensionSource
    let applicationDisplayName: String
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

    var id: String { source.extensionBundleIdentifier }
    var iconData: Data? { iconPayload?.data }
}
