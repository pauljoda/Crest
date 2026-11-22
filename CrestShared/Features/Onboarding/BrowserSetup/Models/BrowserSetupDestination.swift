import Foundation

/// A page the setup steps lead to, over the first page that lists them: a
/// step's own page, or a page deeper in its step.
struct BrowserSetupDestination: Hashable, Sendable {
    // MARK: - Static Variables

    static let bring = BrowserSetupDestination(kind: .bring, step: .bring)
    /// The Spaces the chosen browser brings in.
    static let source = BrowserSetupDestination(kind: .source, step: .bring)
    /// The person's first Space, made here when no other browser brings any.
    static let yourSpace = BrowserSetupDestination(kind: .yourSpace, step: .yourSpace)
    static let spaces = BrowserSetupDestination(kind: .spaces, step: .spaces)
    /// The default browser, the search and ad blocking, last.
    static let home = BrowserSetupDestination(kind: .home, step: .home)

    /// Each step's own page, in the steps' order.
    static let stepPages = [bring, yourSpace, spaces, home]

    // MARK: - Types

    /// The page builders switch on the kind to choose a page's view.
    enum Kinds: Sendable {
        case bring
        case source
        case yourSpace
        case spaces
        case space
        case home
    }

    // MARK: - Variables

    let kind: Kinds
    /// The step the page belongs to, which Back names from a page deeper in
    /// the step.
    let step: BrowserSetupStep
    /// The Space a Space's page edits.
    let spaceID: UUID?

    /// The name of the step the page belongs to.
    var title: LocalizedStringResource { step.title }

    /// The page of this page's step, for a page deeper in the step, where
    /// Back leads when no other page is under it; nil for a step's own page.
    var stepPage: BrowserSetupDestination? {
        let page = Self.stepPages.first { $0.step == step }
        return page == self ? nil : page
    }

    // MARK: - Initializers

    private init(kind: Kinds, step: BrowserSetupStep, spaceID: UUID? = nil) {
        self.kind = kind
        self.step = step
        self.spaceID = spaceID
    }

    // MARK: - Actions - Pages

    /// The page of the Space `spaceID`.
    static func space(_ spaceID: UUID) -> BrowserSetupDestination {
        BrowserSetupDestination(kind: .space, step: .spaces, spaceID: spaceID)
    }
}
