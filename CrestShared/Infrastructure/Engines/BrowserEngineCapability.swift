import Foundation

/// A feature an engine adapter declares to the core and to shared UI. The raw
/// values are the descriptor's wire spelling and match
/// `CrestCore.Contracts.Protocol.EngineCapabilities`.
enum BrowserEngineCapability: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case pages
    case navigation
    case find
    case zoom
    case interactionState = "interaction-state"
    case pageResidency = "page-residency"
    case popups
    case workspaceProfiles = "workspace-profiles"
    case workspaceTransfer = "workspace-transfer"
    case profileDeletion = "profile-deletion"
    case contentBlocking = "content-blocking"
    case downloads
    case permissions
    case reader
    case translation
    case selectionTranslation = "selection-translation"
    case localFiles = "local-files"
    case extensions
    case viewportCapture = "viewport-capture"
    case fullPageCapture = "full-page-capture"
    case pdf
    case webArchive = "web-archive"
    case print
    case inspector
    case featureFlags = "feature-flags"
    case beforeUnload = "before-unload"
    case internalPages = "internal-pages"
}
