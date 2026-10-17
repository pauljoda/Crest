import Foundation

/// What happens when a person shares a link to Crest: it opens right away
/// where Crest routes links, or the share sheet first asks for a Space.
struct BrowserSharedLinkOpening: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let immediately = BrowserSharedLinkOpening(
        name: "immediately", asksForSpace: false, title: "Open Right Away")
    static let choosingSpace = BrowserSharedLinkOpening(
        name: "choose-space", asksForSpace: true, title: "Choose a Space")
    static let all = [immediately, choosingSpace]

    private static let storageKey = "crest.share.link-opening"

    // MARK: - Variables

    let name: String
    /// Whether the share sheet asks which Space the link opens in.
    let asksForSpace: Bool
    let title: LocalizedStringResource

    var id: String { name }

    // MARK: - Initializers

    private init(name: String, asksForSpace: Bool, title: LocalizedStringResource) {
        self.name = name
        self.asksForSpace = asksForSpace
        self.title = title
    }

    // MARK: - Actions - Storage

    /// The choice `defaults` holds, or opening right away when it holds none.
    static func stored(in defaults: UserDefaults) -> BrowserSharedLinkOpening {
        let name = defaults.string(forKey: storageKey)
        return all.first { $0.name == name } ?? .immediately
    }

    func store(in defaults: UserDefaults) {
        defaults.set(name, forKey: Self.storageKey)
    }
}

/// A choice is its stored spelling; the title only describes it.
extension BrowserSharedLinkOpening {
    static func == (lhs: BrowserSharedLinkOpening, rhs: BrowserSharedLinkOpening) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
