import Foundation

/// How the Space switcher shows every Space: its icon, or a plain dot whose
/// shade says which Space is shown and which share its group.
struct BrowserSpaceIconDisplay: Hashable, Sendable, Identifiable {
    // MARK: - Static Variables

    static let icons = BrowserSpaceIconDisplay(name: "icons", title: "Icons", showsDots: false)
    static let dots = BrowserSpaceIconDisplay(name: "dots", title: "Dots", showsDots: true)
    static let all = [icons, dots]

    // MARK: - Variables

    /// The persisted spelling.
    let name: String
    let title: LocalizedStringResource
    /// Whether the switcher draws dots in place of icons, with no track,
    /// group outline or highlight.
    let showsDots: Bool
    var id: String { name }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, showsDots: Bool) {
        self.name = name
        self.title = title
        self.showsDots = showsDots
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> BrowserSpaceIconDisplay? {
        all.first { $0.name == name }
    }
}

// MARK: - Hashable

extension BrowserSpaceIconDisplay {
    static func == (lhs: BrowserSpaceIconDisplay, rhs: BrowserSpaceIconDisplay) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
