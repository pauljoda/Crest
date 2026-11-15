import Foundation

/// Where a window shows a page's address, navigation and site controls: in the
/// sidebar, or in a bar along the top of every page's card. Stored by name, on
/// this device only.
///
/// The two instances below are the one table of what each placement draws.
struct BrowserAddressBarPlacement: Hashable, Sendable, Identifiable {
    // MARK: - Static Variables

    /// The sidebar holds the navigation strip, the address field and the pinned
    /// extensions above the tabs.
    static let sidebar = BrowserAddressBarPlacement(name: "sidebar", title: "Sidebar", showsBarInPageCards: false)

    /// Every page's card carries the bar along its top edge, one bar per card
    /// in a split, and the sidebar keeps only what is not the page's.
    static let top = BrowserAddressBarPlacement(name: "top", title: "Top", showsBarInPageCards: true)

    static let all = [sidebar, top]
    static let standard = sidebar

    // MARK: - Variables

    /// The persisted spelling.
    let name: String
    let title: LocalizedStringResource
    /// Whether each page's card carries the address bar, and the sidebar leaves
    /// out its navigation strip, address field and pinned extensions.
    let showsBarInPageCards: Bool

    var id: String { name }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, showsBarInPageCards: Bool) {
        self.name = name
        self.title = title
        self.showsBarInPageCards = showsBarInPageCards
    }

    // MARK: - Actions - Persistence

    /// The placement stored as `name`, or nil for a spelling this build does
    /// not know.
    static func named(_ name: String?) -> BrowserAddressBarPlacement? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserAddressBarPlacement, rhs: BrowserAddressBarPlacement) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
