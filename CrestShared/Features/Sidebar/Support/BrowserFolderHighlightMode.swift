import Foundation

/// Which folders keep the existing highlight when the pointer leaves.
struct BrowserFolderHighlightMode: RawRepresentable, Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let all = Self(rawValue: "all", title: "All", expanded: true, collapsed: true)
    static let expanded = Self(rawValue: "expanded", title: "Expanded", expanded: true, collapsed: false)
    static let off = Self(rawValue: "off", title: "Off", expanded: false, collapsed: false)
    static let options: [Self] = [all, expanded, off]

    // MARK: - Variables

    let rawValue: String
    let title: LocalizedStringResource
    private let showsExpanded: Bool
    private let showsCollapsed: Bool
    var id: String { rawValue }

    // MARK: - Initializers

    init?(rawValue: String) {
        guard let mode = Self.options.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = mode
    }

    private init(rawValue: String, title: LocalizedStringResource, expanded: Bool, collapsed: Bool) {
        self.rawValue = rawValue
        self.title = title
        self.showsExpanded = expanded
        self.showsCollapsed = collapsed
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }

    func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    // MARK: - Actions - Visibility

    func showsHighlight(isExpanded: Bool) -> Bool { isExpanded ? showsExpanded : showsCollapsed }
}
