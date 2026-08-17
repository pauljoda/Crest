import Foundation
import Observation

struct BrowserExtensionInstallation:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    let spaceID: SpaceID
    let packageName: String
    var source: BrowserExtensionInstallationSource? = nil
    var displayName: String
    var version: String?
    var requestedPermissions: [String]
    var requestedHosts: [String]
    var unsupportedAPIs: [String]
    var errors: [String]
    var isEnabled: Bool
    var permissionSnapshot: BrowserExtensionPermissionSnapshot
    let installedAt: Date
    var modifiedAt: Date
    var sourceDisplayName: String? = nil
    var iconData: Data? = nil
    var hasOptionsPage: Bool? = nil
    var hasCommands: Bool? = nil
    var isPinned: Bool? = nil
    var commandShortcutOverrides: [String: BrowserExtensionCommandShortcutOverride]? = nil
}
