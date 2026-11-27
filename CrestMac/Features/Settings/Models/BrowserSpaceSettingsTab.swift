import SwiftUI

/// The pages of one Space in Settings, in the order its tab bar shows them.
struct BrowserSpaceSettingsTab: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each page shows its own pane. ``BrowserSettingsSpacePage`` switches on
    /// the kind to choose that pane's concrete view.
    enum Kinds: Sendable {
        case appearance
        case browsing
        case privacy
        case extensions
    }

    // MARK: - Static Variables

    static let appearance = BrowserSpaceSettingsTab(
        kind: .appearance, name: "appearance", title: "Appearance",
        sections: [.crestStudio], destination: .spaces)
    static let browsing = BrowserSpaceSettingsTab(
        kind: .browsing, name: "browsing", title: "Browsing",
        sections: [.spaceBrowsing, .spaceAutofill, .spaceSeparatePinnedTabs, .spaceDownloads, .spaceDeletion])
    static let privacy = BrowserSpaceSettingsTab(
        kind: .privacy, name: "privacy", title: "Privacy",
        sections: [.spaceLock, .dataRetention, .sitePermissions, .websiteData, .clearBrowsingData])
    static let extensions = BrowserSpaceSettingsTab(
        kind: .extensions, name: "extensions", title: "Extensions",
        sections: [.installedExtensions], destination: .extensions,
        requiredCapability: .extensions)

    /// Every page, in tab-bar order.
    static let all: [BrowserSpaceSettingsTab] = [appearance, browsing, privacy, extensions]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource

    /// The sections the page draws, in order: what finds it from the
    /// Settings search field beyond its title.
    let sections: [BrowserSettingsSection]

    /// The settings destination whose subject this page holds for one Space,
    /// so a request for that destination opens this page instead.
    let destination: BrowserSettingsDestination?

    /// The engine capability the page's subject depends on.
    let requiredCapability: EngineCapability?

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, sections: [BrowserSettingsSection],
        destination: BrowserSettingsDestination? = nil, requiredCapability: EngineCapability? = nil
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.sections = sections
        self.destination = destination
        self.requiredCapability = requiredCapability
    }

    // MARK: - Actions - Lookup

    /// The page that holds `destination` for one Space, if it has one.
    static func holding(_ destination: BrowserSettingsDestination) -> BrowserSpaceSettingsTab? {
        all.first { $0.destination == destination }
    }

    static func named(_ name: String) -> BrowserSpaceSettingsTab? {
        all.first { $0.name == name }
    }

    /// Whether this page exists for the engines the device runs.
    @MainActor
    func isProvided(in state: CoreState) -> Bool {
        requiredCapability.map(state.offers) ?? true
    }

    /// The tabs the device offers, in order.
    @MainActor
    static func provided(in state: CoreState) -> [BrowserSpaceSettingsTab] {
        all.filter { $0.isProvided(in: state) }
    }

    /// The first tab whose title or sections match a search, if any.
    @MainActor
    static func matching(_ query: String, locale: Locale, in state: CoreState) -> BrowserSpaceSettingsTab? {
        provided(in: state).first { tab in
            var title = tab.title
            title.locale = locale
            return String(localized: title).localizedStandardContains(query)
                || tab.firstSection(matching: query, locale: locale, in: state) != nil
        }
    }

    /// Every section of every page the device offers, in tab-bar and drawing
    /// order, whose words the query finds, each with the page it's on, which a
    /// search lists under each Space.
    @MainActor
    static func sections(
        matching query: String, locale: Locale, in state: CoreState
    ) -> [(tab: BrowserSpaceSettingsTab, section: BrowserSettingsSection)] {
        provided(in: state).flatMap { tab in
            tab.sections
                .filter { $0.isProvided(in: state) && $0.matchesSearchQuery(query, locale: locale) }
                .map { (tab: tab, section: $0) }
        }
    }

    /// The first section on the page, in drawing order, whose words the query
    /// finds, where a search result opens the page.
    @MainActor
    func firstSection(matching query: String, locale: Locale, in state: CoreState) -> BrowserSettingsSection? {
        sections.first { $0.isProvided(in: state) && $0.matchesSearchQuery(query, locale: locale) }
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSpaceSettingsTab, rhs: BrowserSpaceSettingsTab) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// What a route into a Space's page asks it to do on arrival.
enum BrowserSettingsSpaceIntent: Equatable, Sendable {
    case none
    /// Put the Space's name into editing.
    case rename
    /// A Space just made: name it, then pick where its crest starts.
    case newSpace
}
