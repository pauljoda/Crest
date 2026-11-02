import Foundation

/// A change to a Space's group that the person confirms first: making a Space
/// a Sub-Space of another group, or separating a Sub-Space from its group. It
/// carries what the confirmation says, the Spaces that must be unlocked
/// before it runs, and the change itself, which the core applies.
@MainActor
struct BrowserSpaceGroupChange: Identifiable {
    // MARK: - Variables

    let id = UUID()
    /// The Space the change moves.
    let spaceID: UUID
    /// The Spaces the device owner unlocks before the change runs: both sides
    /// of a join, since a join may raise or share protection.
    let unlocking: [SpaceModel]
    let title: String
    let message: String
    let confirmation: String
    /// Whether the change puts a Space into a group, which builds that predate
    /// Sub-Spaces show on its own.
    let formsGroup: Bool
    private let change: @MainActor (BrowserStore) throws(Rejection) -> Void

    // MARK: - Initializers

    private init(
        spaceID: UUID, unlocking: [SpaceModel], title: String, message: String, confirmation: String,
        formsGroup: Bool, change: @escaping @MainActor (BrowserStore) throws(Rejection) -> Void
    ) {
        self.spaceID = spaceID
        self.unlocking = unlocking
        self.title = title
        self.message = message
        self.confirmation = confirmation
        self.formsGroup = formsGroup
        self.change = change
    }

    /// Makes `space` a Sub-Space of the group `group` belongs to, which keeps
    /// its session; nil when `space` may not join one.
    static func joining(
        _ space: SpaceModel, into group: SpaceModel, in browser: BrowserStore
    ) -> BrowserSpaceGroupChange? {
        guard browser.canJoinGroup(space), browser.primary(of: group) !== browser.primary(of: space) else { return nil }
        let name = space.settings.name
        let target = browser.primary(of: group)
        let targetName = target.settings.name
        return BrowserSpaceGroupChange(
            spaceID: space.id, unlocking: [space, target],
            title: String(localized: "Make “\(name)” a Sub-Space of “\(targetName)”?"),
            message: String(
                localized: """
                    \(name) will use \(targetName)’s sign-ins, history and extensions. Its own sign-ins and website \
                    data stay on this device and come back if you separate it.
                    """),
            confirmation: String(localized: "Make Sub-Space"), formsGroup: true,
            change: { browser throws(Rejection) in try browser.join(space.id, toGroupOf: target.id) })
    }

    /// Separates the Sub-Space `space` from its group; nil for a Space that is
    /// not a Sub-Space.
    static func separating(_ space: SpaceModel, in browser: BrowserStore) -> BrowserSpaceGroupChange? {
        guard browser.isSubSpace(space) else { return nil }
        let name = space.settings.name
        let primaryName = browser.primary(of: space).settings.name
        return BrowserSpaceGroupChange(
            spaceID: space.id, unlocking: [space],
            title: String(localized: "Separate “\(name)” from “\(primaryName)”?"),
            message: String(localized: "\(name) will use sign-ins and extensions of its own. It keeps its tabs."),
            confirmation: String(localized: "Separate"), formsGroup: false,
            change: { browser throws(Rejection) in try browser.separate(space.id) })
    }

    // MARK: - Actions - Applying

    /// Applies the change through `browser`'s core. Throws the rule the core
    /// refused it with.
    func apply(in browser: BrowserStore) throws(Rejection) {
        try change(browser)
    }
}
