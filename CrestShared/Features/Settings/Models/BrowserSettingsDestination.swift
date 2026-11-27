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
/// (`settings-<name>` rows and `settings-form-<name>` forms), so the names
/// below cannot change without breaking the automation suites.
struct BrowserSettingsDestination: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each destination opens its own pane. ``BrowserSettingsDestinationRouter``
    /// switches on the kind to choose that pane's concrete view.
    enum Kinds: Sendable {
        case general
        case tabs
        case search
        case engines
        case lookAndFeel
        case links
        case shortcuts
        case spaces
        case sync
        case privacy
        case adBlocking
        case passwords
        case extensions
        case featureFlags
        case advanced
        case about
        case agents
    }

    // MARK: - Static Variables

    // Pages whose sections differ by platform list each platform's own.
    #if os(macOS)
        private static let platformGeneralSections: [BrowserSettingsSection] = [
            .defaultBrowser, .startup, .translation, .webpages, .pictureInPicture, .developerToolbar, .quitting,
        ]
        private static let platformTabsSections: [BrowserSettingsSection] = [
            .newTabs, .durableTabs, .splitFocus, .recentTabs, .tidy, .sidebarWidgets,
        ]
        /// The Mac shows each Space's pages instead of a Spaces page; these
        /// keep the command palette's Spaces result findable by their words.
        private static let platformSpacesSections: [BrowserSettingsSection] = [
            .crestStudio, .spaceBrowsing, .spaceAutofill, .spaceSeparatePinnedTabs, .spaceDownloads, .spaceDeletion,
        ]
        /// Each Space's own privacy is a page of that Space.
        private static let platformPrivacySections: [BrowserSettingsSection] = [.systemPermissions, .spacePrivacyPages]
        private static let platformAboutSections: [BrowserSettingsSection] = [
            .version, .softwareUpdates, .whatsNew, .community,
        ]
    #else
        private static let platformGeneralSections: [BrowserSettingsSection] = [
            .defaultBrowser, .startup, .floatingSidebar, .translation,
        ]
        private static let platformTabsSections: [BrowserSettingsSection] = [
            .newTabs, .durableTabs, .tidy, .sidebarWidgets,
        ]
        private static let platformSpacesSections: [BrowserSettingsSection] = [
            .spaceList, .spaceGroup, .spaceCustomization, .spaceBrowsing, .spaceSeparatePinnedTabs, .spaceLock,
            .spaceDownloads, .spaceDeletion, .crestStudio,
        ]
        private static let platformPrivacySections: [BrowserSettingsSection] = [
            .privacySpace, .spaceLock, .dataRetention, .sitePermissions, .websiteData, .clearBrowsingData,
        ]
        private static let platformAboutSections: [BrowserSettingsSection] = [.version, .whatsNew, .community]
    #endif

    // Each destination is a tile of Crest's paper in one of its brand colors,
    // its glyph solid, the colors taken in turn so neighbouring rows never
    // share one on either platform.
    static let general = BrowserSettingsDestination(
        kind: .general, name: "general", title: "General", subtitle: "Browsing and startup",
        sections: platformGeneralSections,
        symbol: "gearshape.fill", color: CrestBrandPalette.crestBlue)
    static let tabs = BrowserSettingsDestination(
        kind: .tabs, name: "tabs", title: "Tabs", subtitle: "New, pinned and saved tabs",
        sections: platformTabsSections,
        symbol: "square.fill.on.square.fill", color: CrestBrandPalette.sky)
    static let search = BrowserSettingsDestination(
        kind: .search, name: "search", title: "Search", subtitle: "Search engine, command palette and site searches",
        sections: [.defaultSearch, .paletteResults, .paletteTyping, .searchProviders],
        symbol: "magnifyingglass", color: CrestBrandPalette.butter)
    static let lookAndFeel = BrowserSettingsDestination(
        kind: .lookAndFeel, name: "lookAndFeel", title: "Appearance", subtitle: "Window, tabs, zoom and motion",
        sections: [
            .addressBar, .spaceIcons, .windowAppearance, .pageZoom, .tabAppearance, .tabStatus, .addressAppearance,
            .folderAppearance, .groupAppearance, .hoverPreviews, .appIcon, .moreCustomization, .resetAppearance,
        ],
        symbol: "paintpalette.fill", color: CrestBrandPalette.coral)
    static let engines = BrowserSettingsDestination(
        kind: .engines, name: "engines", title: "Engines", subtitle: "Default engine and website rules",
        sections: [.defaultEngine, .engineRules],
        symbol: "cpu.fill", color: CrestBrandPalette.crestBlue, platforms: [.desktop])
    static let links = BrowserSettingsDestination(
        kind: .links, name: "links", title: "Links", subtitle: "Quick Window and Peek",
        sections: [.externalLinks, .quickWindow, .peek, .linkRouting], symbol: "link",
        color: CrestBrandPalette.sage)
    static let shortcuts = BrowserSettingsDestination(
        kind: .shortcuts, name: "shortcuts", title: "Shortcuts", subtitle: "Keyboard commands",
        sections: [.keyboardShortcuts],
        symbol: "keyboard.fill",
        color: CrestBrandPalette.butter, platforms: [.desktop])
    static let spaces = BrowserSettingsDestination(
        kind: .spaces, name: "spaces", title: "Spaces", subtitle: "Profiles and appearance",
        sections: platformSpacesSections,
        symbol: "square.grid.2x2.fill", color: CrestBrandPalette.crestBlue)
    static let sync = BrowserSettingsDestination(
        kind: .sync, name: "sync", title: "Sync", subtitle: "iCloud setup and status",
        sections: [.iCloud, .syncConflict, .syncScope, .syncDiagnostics],
        symbol: "arrow.triangle.2.circlepath.icloud.fill", color: CrestBrandPalette.sky)
    // The macOS sidebar row cannot fit "Privacy & Permissions" on one line at
    // its compact row height.
    static let privacy = BrowserSettingsDestination(
        kind: .privacy, name: "privacy", title: "Privacy & Permissions", navigationTitle: "Privacy",
        subtitle: "Site access and data",
        sections: platformPrivacySections,
        symbol: "hand.raised.fill", color: CrestBrandPalette.coral)
    static let adBlocking = BrowserSettingsDestination(
        kind: .adBlocking, name: "adBlocking", title: "Ad Blocking", subtitle: "Filter lists, your rules and sites",
        sections: [.adBlockingLevel, .filterLists, .customFilterLists, .customFilters, .blockingSites],
        symbol: "shield.fill", color: CrestBrandPalette.sage, requiredCapability: .contentBlocking)
    static let passwords = BrowserSettingsDestination(
        kind: .passwords, name: "passwords", title: "Autofill", subtitle: "Passwords, codes, addresses and cards",
        sections: [.passwordsSpace, .crestPasswords, .savedPasswords, .systemPasskeys, .addresses, .paymentCards],
        symbol: "key.fill",
        color: CrestBrandPalette.butter)
    static let extensions = BrowserSettingsDestination(
        kind: .extensions, name: "extensions", title: "Extensions", subtitle: "Space extensions and permissions",
        sections: [.extensionsSpace, .installedExtensions],
        symbol: "puzzlepiece.extension.fill", color: CrestBrandPalette.sky,
        requiredCapability: .extensions)
    static let featureFlags = BrowserSettingsDestination(
        kind: .featureFlags, name: "featureFlags", title: "Feature Flags", subtitle: "Engine experiments",
        sections: [.engineFeatureFlags],
        symbol: "flag.2.crossed.fill", color: CrestBrandPalette.coral,
        requiredCapability: .featureFlags, platforms: [.desktop])
    static let advanced = BrowserSettingsDestination(
        kind: .advanced, name: "advanced", title: "Advanced", subtitle: "Import, export, and runtime",
        sections: [.setup, .featureFlagsLink, .dataPortability], symbol: "switch.2",
        color: CrestBrandPalette.coral)
    static let agents = BrowserSettingsDestination(
        kind: .agents, name: "agents", title: "Agents", subtitle: "Coding agents and scripts",
        sections: [.agentAccess, .agentConnection, .agentSpaces, .agentScripts, .agentSessions, .allowedAgents],
        symbol: "sparkles", color: CrestBrandPalette.butter, platforms: [.desktop])
    static let about = BrowserSettingsDestination(
        kind: .about, name: "about", title: "About", subtitle: "Version, updates, and support",
        sections: platformAboutSections,
        symbol: "info.circle.fill", color: CrestBrandPalette.sky)

    /// Every destination, in catalog order.
    static let all: [BrowserSettingsDestination] = [
        general, tabs, search, engines, lookAndFeel, links, shortcuts, spaces, sync, privacy, adBlocking, passwords,
        extensions, featureFlags, agents, advanced, about,
    ]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource

    /// The title where space is tight enough that the full name wraps.
    let navigationTitle: LocalizedStringResource

    let subtitle: LocalizedStringResource

    /// The sections this platform draws on the destination's page, in the
    /// order it draws them. They are its search vocabulary beyond its title
    /// and subtitle, so nothing on the page can go unsearchable. A page that
    /// draws its own list rather than a ``BrowserSettingsPane``, such as
    /// Shortcuts or Feature Flags, names one section for the whole page.
    let sections: [BrowserSettingsSection]

    let symbol: String

    /// The brand color that fills the destination's tile.
    let color: Color

    /// The engine capability the destination's whole subject depends on. An
    /// engine without it never offers the destination.
    let requiredCapability: EngineCapability?

    /// The platforms whose shells host the destination: every one, or only
    /// the Mac for a subject only the Mac has, such as the engine choice,
    /// rebindable keyboard commands, WebKit's private feature registry and
    /// the agents server.
    let platforms: Set<DevicePlatform>

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, navigationTitle: LocalizedStringResource? = nil,
        subtitle: LocalizedStringResource, sections: [BrowserSettingsSection], symbol: String,
        color: Color, requiredCapability: EngineCapability? = nil,
        platforms: Set<DevicePlatform> = Set(DevicePlatform.all)
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.navigationTitle = navigationTitle ?? title
        self.subtitle = subtitle
        self.sections = sections
        self.symbol = symbol
        self.color = color
        self.requiredCapability = requiredCapability
        self.platforms = platforms
    }

    // MARK: - Actions - Platform capability

    /// The destinations this platform can present, in catalog order, whose
    /// subject the device offers.
    ///
    /// Shells iterate this rather than `all` so a destination that only one
    /// platform can host stays out of the other's list.
    @MainActor
    static func platformCases(in state: CoreState) -> [BrowserSettingsDestination] {
        all.filter { $0.platforms.contains(.current) && $0.isProvided(in: state) }
    }

    /// The destinations a list shows: those this platform presents and the
    /// device offers, matching `searchText`. A match inside a page that lives
    /// under another lists the page `parent` names for it.
    @MainActor
    static func visible(
        matching searchText: String, locale: Locale, in state: CoreState,
        parent: (BrowserSettingsDestination) -> BrowserSettingsDestination? = { _ in nil }
    ) -> [BrowserSettingsDestination] {
        let provided = platformCases(in: state)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return provided }
        let matches = provided.filter { $0.matchesSearchQuery(query, locale: locale, in: state) }
        return provided.filter { destination in
            matches.contains(destination) || matches.contains { parent($0) == destination }
        }
    }

    /// Whether the device offers the destination's subject at all: the
    /// default engine or an engine a page is open on provides it.
    ///
    /// The set is fixed: accessibility identifiers derive from it and the
    /// automation suites pin it, so a destination never disappears from the
    /// catalog because of which engines this process registered. Only its
    /// availability follows what they offer.
    @MainActor
    func isProvided(in state: CoreState) -> Bool {
        requiredCapability.map(state.offers) ?? true
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSettingsDestination, rhs: BrowserSettingsDestination) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
