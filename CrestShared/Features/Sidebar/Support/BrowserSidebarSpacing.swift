import CoreGraphics
import Foundation

/// How much room the sidebar keeps between what it stacks: its rows, the
/// address field, the pins, and the headers of its sections.
///
/// Each choice is a share of the room the sidebar is designed with. The rows
/// themselves keep the size the tab size gives them.
struct BrowserSidebarSpacing: Hashable, Sendable, Identifiable {
    // MARK: - Static Variables

    /// No room between rows, and the least between everything else.
    static let none = BrowserSidebarSpacing(name: "none", title: "None", factor: 0)
    static let tight = BrowserSidebarSpacing(name: "tight", title: "Tight", factor: 0.5)
    /// The room the sidebar is designed with.
    static let standard = BrowserSidebarSpacing(name: "default", title: "Default", factor: 1)
    static let relaxed = BrowserSidebarSpacing(name: "relaxed", title: "Relaxed", factor: 1.5)
    static let all = [none, tight, standard, relaxed]

    // MARK: - Variables

    /// The persisted spelling.
    let name: String
    let title: LocalizedStringResource
    /// The share of the designed room this choice keeps.
    let factor: Double
    var id: String { name }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, factor: Double) {
        self.name = name
        self.title = title
        self.factor = factor
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> BrowserSidebarSpacing? {
        all.first { $0.name == name }
    }

    // MARK: - Actions - Room

    /// The room this choice keeps where the sidebar is designed with
    /// `standard`, and never less than `minimum`.
    func gap(_ standard: CGFloat, minimum: CGFloat = 0) -> CGFloat {
        max(minimum, standard * CGFloat(factor))
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarSpacing, rhs: BrowserSidebarSpacing) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
