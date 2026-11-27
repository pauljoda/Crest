import SwiftUI

/// One section of a settings page: the words that find it from the Settings
/// search field.
///
/// A page draws a section only through a ``BrowserSettingsSectionSlot`` naming
/// one of these, and lists the same sections on its destination, so a section
/// that is on screen is always in the page's search index. The instances live
/// in one `BrowserSettingsSection+<Page>.swift` file per page.
///
/// `name` is the section's identity, which the slot's scroll anchor
/// derives from.
struct BrowserSettingsSection: Hashable, Identifiable, Sendable {
    // MARK: - Variables

    let name: String

    /// The section's heading, or what it is about where it shows none.
    let title: LocalizedStringResource

    /// Localized vocabulary that finds the section beyond its title: the
    /// names of its settings and the words a person might use for them.
    let searchTerms: LocalizedStringResource

    /// The engine capability the section's subject depends on.
    let requiredCapability: EngineCapability?

    var id: String { name }

    // MARK: - Initializers

    /// Instances are made only in the `BrowserSettingsSection+<Page>.swift`
    /// files, one static instance per section.
    init(
        name: String, title: LocalizedStringResource, searchTerms: LocalizedStringResource,
        requiredCapability: EngineCapability? = nil
    ) {
        self.name = name
        self.title = title
        self.searchTerms = searchTerms
        self.requiredCapability = requiredCapability
    }

    // MARK: - Actions - Availability

    /// Whether the device offers the section's subject. A page lists only the
    /// sections its platform draws, so the platform is already settled.
    @MainActor
    func isProvided(in state: CoreState) -> Bool {
        requiredCapability.map(state.offers) ?? true
    }

    // MARK: - Actions - Search

    /// The section's title and terms in `locale`, for filtering only.
    func searchIndex(locale: Locale) -> String {
        [title, searchTerms]
            .map { resource in
                var localizedResource = resource
                localizedResource.locale = locale
                return String(localized: localizedResource)
            }
            .joined(separator: " ")
    }

    func matchesSearchQuery(_ query: String, locale: Locale) -> Bool {
        searchIndex(locale: locale).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        ) != nil
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSettingsSection, rhs: BrowserSettingsSection) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
