import SwiftUI

/// The one settings catalog both shells navigate.
///
/// macOS presents these in a `NavigationSplitView` sidebar; iOS presents them in a
/// `NavigationSplitView` or `NavigationStack` sheet. Each shell keeps its own
/// navigation and pane content — this type owns only the *identity* of a
/// destination: what it is called, how it is described, which glyph and brand
/// hue stand for it, and which words find it in search.
///
/// `rawValue` is a shipped contract: accessibility identifiers derive from it
/// (`settings-<rawValue>` rows on both platforms, plus
/// `settings-header-<rawValue>` and `settings-form-<rawValue>` on iOS), so the
/// strings below cannot change without breaking the automation suites.
/// `BrowserSettingsDestinationTests` pins them.
enum BrowserSettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case general
    case lookAndFeel
    case links
    case shortcuts
    case spaces
    case sync
    case privacy
    case passwords
    case extensions
    case featureFlags
    case advanced
    case about

    var id: String { rawValue }

    // MARK: - Platform capability

    /// The destinations this platform can present, in catalog order.
    ///
    /// Shells iterate this rather than `allCases` so a destination that only
    /// one platform can host stays out of the other's list.
    static var platformCases: [BrowserSettingsDestination] {
        BrowserPlatformSettingsDestinationCatalog.cases
            .filter(\.isProvidedByCurrentEngine)
    }

    /// Whether the running engine provides the destination's subject at all.
    ///
    /// The case set is fixed: accessibility identifiers derive from it and the
    /// automation suites pin it, so a destination never disappears from the
    /// enum because of which engine this process composed. Only its
    /// availability follows the engine's declared capabilities.
    var isProvidedByCurrentEngine: Bool {
        switch self {
        case .extensions: BrowserEngineRegistration.current.supports("extensions")
        default: true
        }
    }

    /// Whether this platform can present the destination at all.
    ///
    /// Keyboard shortcuts are a desktop concern: iOS has no rebindable command
    /// table to edit, so `.shortcuts` is absent there.
    var isAvailableOnCurrentPlatform: Bool {
        isProvidedByCurrentEngine
            && BrowserPlatformSettingsDestinationCatalog.isAvailable(self)
    }

    // MARK: - Identity

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .lookAndFeel: "paintpalette"
        case .links: "link"
        case .shortcuts: "keyboard"
        case .spaces: "square.grid.2x2"
        case .sync: "arrow.triangle.2.circlepath.icloud"
        case .privacy: "hand.raised"
        case .extensions: "puzzlepiece.extension"
        case .passwords: "key.fill"
        case .featureFlags: "flag.2.crossed"
        case .advanced: "switch.2"
        case .about: "info.circle"
        }
    }

    /// The brand hue that stands for the destination.
    ///
    /// These are the website palette's fixed hues rather than system colors, so
    /// a destination reads the same on both platforms and in both appearances.
    var color: Color {
        switch self {
        case .general: CrestBrandPalette.inkSoft
        case .lookAndFeel: CrestBrandPalette.coral
        case .links: CrestBrandPalette.sky
        case .shortcuts: CrestBrandPalette.butter
        case .spaces: CrestBrandPalette.coral
        case .sync: CrestBrandPalette.sage
        case .privacy: CrestBrandPalette.inkSoft
        case .extensions: CrestBrandPalette.sage
        case .passwords: CrestBrandPalette.butter
        case .featureFlags: CrestBrandPalette.coral
        case .advanced: CrestBrandPalette.sage
        case .about: CrestBrandPalette.sky
        }
    }

}
