import SwiftUI

/// The one settings catalog both shells navigate.
///
/// macOS presents these in a `NavigationSplitView` sidebar; iOS presents them in a
/// `NavigationSplitView` or `NavigationStack` sheet. Each shell keeps its own
/// navigation and pane content — this type owns only the *identity* of a
/// destination: what it is called, how it is described, which glyph and brand
/// hue stand for it, and which words find it in search.
///
/// `name` is a shipped contract: accessibility identifiers derive from it
/// (`settings-<name>` rows on both platforms, plus `settings-header-<name>`
/// and `settings-form-<name>` on iOS), so the names below cannot change without
/// breaking the automation suites.
struct BrowserSettingsDestination: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each destination opens its own pane, so the one place that builds a
    /// pane switches over the kind.
    enum Kinds: Sendable {
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
    }

    // MARK: - Variables

    // The hues are the website palette's fixed hues rather than system colors,
    // so a destination reads the same on both platforms and in both appearances.
    static let general = BrowserSettingsDestination(
        kind: .general, name: "general", title: "General", subtitle: "Browsing and startup",
        searchTerms:
            "browser startup default Space typing spelling spell check text editing focus new tabs follow move between Spaces Command-click middle-click pinned saved close resume restore root URL mouse translation system permissions access camera microphone location notifications passkeys files folders downloads allow blocked repair sidebar widgets Now Playing media cards",
        symbol: "gearshape", color: CrestBrandPalette.inkSoft)
    static let lookAndFeel = BrowserSettingsDestination(
        kind: .lookAndFeel, name: "lookAndFeel", title: "Look and Feel", subtitle: "Appearance, zoom, and motion",
        searchTerms:
            "appearance theme transparency page zoom percentage sidebar left right borderless window fullscreen layout interface animation motion page cards folder highlights counts borders preview density spacing padding scale icons",
        symbol: "paintpalette", color: CrestBrandPalette.coral)
    static let links = BrowserSettingsDestination(
        kind: .links, name: "links", title: "Links", subtitle: "Quick Window and Peek",
        searchTerms: "external apps Quick Window Peek pinned saved routing open", symbol: "link",
        color: CrestBrandPalette.sky)
    static let shortcuts = BrowserSettingsDestination(
        kind: .shortcuts, name: "shortcuts", title: "Shortcuts", subtitle: "Keyboard commands",
        searchTerms: "keyboard keys commands rebind remap Arc hotkeys navigation tabs Spaces page", symbol: "keyboard",
        color: CrestBrandPalette.butter)
    static let spaces = BrowserSettingsDestination(
        kind: .spaces, name: "spaces", title: "Spaces", subtitle: "Profiles and appearance",
        searchTerms:
            "profile name identity icon color appearance theme search cleanup isolation reorder browsing archive independence folder intensity text color light dark automatic preview",
        symbol: "square.grid.2x2", color: CrestBrandPalette.coral)
    static let sync = BrowserSettingsDestination(
        kind: .sync, name: "sync", title: "Sync", subtitle: "iCloud setup and status",
        searchTerms: "iCloud CloudKit account upload download conflict status monitor diagnostics pending records",
        symbol: "arrow.triangle.2.circlepath.icloud", color: CrestBrandPalette.sage)
    // The macOS sidebar row cannot fit "Privacy & Permissions" on one line at
    // its compact row height.
    static let privacy = BrowserSettingsDestination(
        kind: .privacy, name: "privacy", title: "Privacy & Permissions", navigationTitle: "Privacy",
        subtitle: "Site access and data",
        searchTerms: "content blocking ads trackers camera microphone site access history cookies data",
        symbol: "hand.raised", color: CrestBrandPalette.inkSoft)
    static let passwords = BrowserSettingsDestination(
        kind: .passwords, name: "passwords", title: "Passwords", subtitle: "Credentials and autofill",
        searchTerms: "credentials autofill iCloud Keychain passkeys synchronization", symbol: "key.fill",
        color: CrestBrandPalette.butter)
    static let extensions = BrowserSettingsDestination(
        kind: .extensions, name: "extensions", title: "Extensions", subtitle: "Space extensions and permissions",
        searchTerms: "extensions permissions Chromium Chrome Web Store install copies Spaces",
        symbol: "puzzlepiece.extension", color: CrestBrandPalette.sage, requiredCapability: .extensions)
    static let featureFlags = BrowserSettingsDestination(
        kind: .featureFlags, name: "featureFlags", title: "Feature Flags", subtitle: "Engine experiments",
        searchTerms: "WebKit Chromium experimental preview testable developer stable runtime flags features",
        symbol: "flag.2.crossed", color: CrestBrandPalette.coral, requiredCapability: .featureFlags)
    static let advanced = BrowserSettingsDestination(
        kind: .advanced, name: "advanced", title: "Advanced", subtitle: "Import, export, and runtime",
        searchTerms: "import export backup portability data records", symbol: "switch.2",
        color: CrestBrandPalette.sage)
    static let about = BrowserSettingsDestination(
        kind: .about, name: "about", title: "About", subtitle: "Version, updates, and support",
        searchTerms:
            "version build updates changelog what's new feedback Reddit GitHub issues roadmap support community",
        symbol: "info.circle", color: CrestBrandPalette.sky)

    /// Every destination, in catalog order.
    static let all: [BrowserSettingsDestination] = [
        general, lookAndFeel, links, shortcuts, spaces, sync, privacy, passwords, extensions, featureFlags,
        advanced, about,
    ]

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource

    /// The title where space is tight enough that the full name wraps.
    let navigationTitle: LocalizedStringResource

    let subtitle: LocalizedStringResource

    /// Localized vocabulary that supplements the visible destination metadata.
    ///
    /// The terms are the union of the vocabulary each platform used before this
    /// catalog was shared, so neither shell loses a search route.
    let searchTerms: LocalizedStringResource

    let symbol: String

    /// The brand hue that stands for the destination.
    let color: Color

    /// The engine capability the destination's whole subject depends on. An
    /// engine without it never offers the destination.
    let requiredCapability: BrowserEngineCapability?

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, navigationTitle: LocalizedStringResource? = nil,
        subtitle: LocalizedStringResource, searchTerms: LocalizedStringResource, symbol: String, color: Color,
        requiredCapability: BrowserEngineCapability? = nil
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.navigationTitle = navigationTitle ?? title
        self.subtitle = subtitle
        self.searchTerms = searchTerms
        self.symbol = symbol
        self.color = color
        self.requiredCapability = requiredCapability
    }

    // MARK: - Actions - Platform capability

    /// The destinations this platform can present, in catalog order.
    ///
    /// Shells iterate this rather than `all` so a destination that only one
    /// platform can host stays out of the other's list.
    static var platformCases: [BrowserSettingsDestination] {
        BrowserPlatformSettingsDestinationCatalog.cases
            .filter(\.isProvidedByCurrentEngine)
    }

    /// Whether the running engine provides the destination's subject at all.
    ///
    /// The set is fixed: accessibility identifiers derive from it and the
    /// automation suites pin it, so a destination never disappears from the
    /// catalog because of which engine this process composed. Only its
    /// availability follows the engine's declared capabilities.
    var isProvidedByCurrentEngine: Bool {
        requiredCapability.map(BrowserEngineRegistration.current.supports) ?? true
    }

    /// Whether this platform can present the destination at all.
    ///
    /// Keyboard shortcuts are a desktop concern: iOS has no rebindable command
    /// table to edit, so `.shortcuts` is absent there.
    var isAvailableOnCurrentPlatform: Bool {
        isProvidedByCurrentEngine
            && BrowserPlatformSettingsDestinationCatalog.isAvailable(self)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSettingsDestination, rhs: BrowserSettingsDestination) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
