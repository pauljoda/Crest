import SwiftUI

/// The pages of one Space in Settings, in the order its tab bar shows them.
/// Each page carries the pane it shows, built from the Space's settings page.
struct BrowserSpaceSettingsTab: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let appearance = BrowserSpaceSettingsTab(
        name: "appearance", title: "Appearance",
        searchTerms: "crest studio name icon emblem colors theme banner background sidebar pattern gradient accent",
        destination: .spaces,
        pane: { page in AnyView(BrowserSpaceEditorView(browser: page.browser, space: page.space)) })
    static let browsing = BrowserSpaceSettingsTab(
        name: "browsing", title: "Browsing",
        searchTerms: "search engine suggestions archive tabs cleanup downloads folder save location delete Space",
        pane: { page in
            AnyView(
                BrowserSettingsPane(.spaces) {
                    BrowserSpaceBrowsingSection(browser: page.browser, space: page.space)
                    BrowserSpaceDownloadsSection(settings: page.downloads.settings(for: page.space))
                    BrowserSpaceDeletionSection(
                        browser: page.browser, spaceID: page.space.id, dataDeleter: page.dataDeleter)
                }
                .task(id: page.space.id) { page.downloads.refresh(for: page.space.id) })
        })
    static let privacy = BrowserSpaceSettingsTab(
        name: "privacy", title: "Privacy",
        searchTerms:
            "privacy lock Touch ID password private history retention archive downloads records content blocking ads trackers site permissions camera microphone location notifications",
        pane: { page in
            AnyView(
                BrowserPrivacySettingsPane(
                    browser: page.browser,
                    downloadCenter: page.pages.downloadCenter,
                    spaceAccess: page.spaceAccess,
                    permissionCenter: page.pages.permissionCenter,
                    contentBlockingErrorDescription: page.pages.contentBlockingErrorDescription,
                    fixedSpaceID: page.space.id
                ))
        })
    static let passwords = BrowserSpaceSettingsTab(
        name: "passwords", title: "Passwords",
        searchTerms: "passwords credentials autofill iCloud Keychain import export", destination: .passwords,
        pane: { page in
            AnyView(
                BrowserPasswordSettingsPane(
                    browser: page.browser,
                    spaceAccess: page.spaceAccess,
                    layout: .macOSSpacePage,
                    searchText: page.$passwordSearchText,
                    fixedSpaceID: page.space.id
                ))
        })
    static let extensions = BrowserSpaceSettingsTab(
        name: "extensions", title: "Extensions",
        searchTerms: "extensions add-ons Chrome Web Store install remove", destination: .extensions,
        requiredCapability: .extensions,
        pane: { page in
            AnyView(
                BrowserEngineExtensionSettingsPane(
                    browser: page.browser, spaceAccess: page.spaceAccess, spaceID: page.space.id))
        })

    /// Every page, in tab-bar order.
    static let all: [BrowserSpaceSettingsTab] = [appearance, browsing, privacy, passwords, extensions]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource

    /// Words that find this page from the Settings search field.
    let searchTerms: LocalizedStringResource

    /// The settings destination whose subject this page holds for one Space,
    /// so a request for that destination opens this page instead.
    let destination: BrowserSettingsDestination?

    /// The engine capability the page's subject depends on.
    let requiredCapability: EngineCapability?

    /// The pane the page shows for one Space.
    let pane: @MainActor @Sendable (BrowserSettingsSpacePage) -> AnyView

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, searchTerms: LocalizedStringResource,
        destination: BrowserSettingsDestination? = nil, requiredCapability: EngineCapability? = nil,
        pane: @escaping @MainActor @Sendable (BrowserSettingsSpacePage) -> AnyView
    ) {
        self.name = name
        self.title = title
        self.searchTerms = searchTerms
        self.destination = destination
        self.requiredCapability = requiredCapability
        self.pane = pane
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

    /// The first tab whose words match a search, if any.
    @MainActor
    static func matching(_ query: String, locale: Locale, in state: CoreState) -> BrowserSpaceSettingsTab? {
        provided(in: state).first { tab in
            [tab.title, tab.searchTerms].contains { resource in
                var resource = resource
                resource.locale = locale
                return String(localized: resource).localizedStandardContains(query)
            }
        }
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
