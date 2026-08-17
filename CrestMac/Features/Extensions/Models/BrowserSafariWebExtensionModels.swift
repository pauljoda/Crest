import AppKit
import Foundation
import Security
import WebKit

struct BrowserSafariWebExtensionAppDescriptor: Equatable, Identifiable, Sendable {
    let applicationURL: URL
    let applicationDisplayName: String
    let applicationBundleIdentifier: String
    let extensionBundleURL: URL
    let extensionBundleIdentifier: String
    let displayName: String
    let version: String?
    let relativeBundlePath: String

    var id: String { extensionBundleIdentifier }
}

enum BrowserSafariWebExtensionAppLocatorError: LocalizedError, Equatable {
    case invalidApplication
    case unreadableApplication

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            "Choose an installed application that contains a Safari Web Extension."
        case .unreadableApplication:
            "Crest couldn’t inspect that application."
        }
    }
}

struct BrowserSafariWebExtensionApplicationMatch:
    Equatable,
    Identifiable,
    Sendable
{
    let applicationURL: URL
    let applicationDisplayName: String
    let descriptors: [BrowserSafariWebExtensionAppDescriptor]

    var id: URL { applicationURL }
}

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

enum BrowserSafariWebExtensionInspectorError: LocalizedError {
    case noWebExtensions(applicationName: String)
    case invalidCodeSignature(itemName: String)
    case missingExtensionBundle

    var errorDescription: String? {
        switch self {
        case .noWebExtensions(let applicationName):
            "\(applicationName) doesn’t contain a Safari Web Extension that Crest can use. Safari App Extensions and legacy content blockers aren’t compatible."
        case .invalidCodeSignature(let itemName):
            "\(itemName) doesn’t have a valid code signature. Crest only loads Safari Web Extensions from signed apps."
        case .missingExtensionBundle:
            "The Safari Web Extension could not be found inside its app."
        }
    }
}
