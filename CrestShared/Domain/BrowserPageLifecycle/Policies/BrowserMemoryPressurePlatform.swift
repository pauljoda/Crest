import Foundation

/// Which residency budget a store asks for. The raw values are the
/// control-plane wire vocabulary for residency policy.
enum BrowserMemoryPressurePlatform: String, Equatable, Sendable {
    case desktop
    case mobile
}
