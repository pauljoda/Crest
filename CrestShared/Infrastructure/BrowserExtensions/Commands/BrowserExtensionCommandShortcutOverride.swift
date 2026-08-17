import Foundation
import Observation

enum BrowserExtensionCommandShortcutOverride:
    Codable,
    Equatable,
    Sendable
{
    case custom(BrowserShortcut)
    case unassigned
}
