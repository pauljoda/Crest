import Foundation

// MARK: - Types

/// A Space the person asked to delete, and whether its Sub-Spaces go with it.
struct BrowserSpaceDeletionRequest: Identifiable, Equatable {
    let spaceID: UUID
    var includesSubSpaces = false

    var id: UUID { spaceID }
}

/// What deleting a Space removes, as its confirmation says it, and how the
/// deletion runs. A Sub-Space goes alone and leaves its group's session; a
/// primary that leads Sub-Spaces hands its group to the one the person
/// chooses, unless the whole group goes; a Space on its own goes with all of
/// its data.
@MainActor
struct BrowserSpaceDeletionPlan: Identifiable {
    // MARK: - Variables

    let request: BrowserSpaceDeletionRequest
    let title: String
    let message: String
    let confirmation: String
    /// The Sub-Spaces of which one takes the group over: empty unless a primary
    /// that leads Sub-Spaces goes alone.
    let successors: [SpaceModel]
    /// The Space whose group must be unlocked first: a primary that hands its
    /// group over moves the group's records, which the lock guards.
    let unlocking: SpaceModel?

    nonisolated var id: UUID { request.spaceID }

    // MARK: - Initializers

    /// The plan for `request` in `browser`'s workspace, or nil once the Space
    /// is gone.
    init?(_ request: BrowserSpaceDeletionRequest, in browser: BrowserStore) {
        guard let space = browser.spaceModel(request.spaceID) else { return nil }
        self.request = request
        let name = space.settings.name
        let subSpaces = browser.groupMembers(of: space).filter { $0 !== space }
        if browser.isSubSpace(space) {
            let primaryName = browser.primary(of: space).settings.name
            title = String(localized: "Delete “\(name)”?")
            message = String(
                localized: "Deletes its tabs. \(primaryName)’s sign-ins, history, passwords and extensions stay.")
            confirmation = String(localized: "Delete Sub-Space")
            successors = []
            unlocking = nil
        } else if subSpaces.isEmpty {
            title = String(localized: "Delete “\(name)”?")
            message = String(
                localized: """
                    This permanently removes this Space’s browser data from Crest. Downloaded files you already \
                    saved are kept.
                    """)
            confirmation = String(localized: "Delete Space and Data")
            successors = []
            unlocking = nil
        } else if request.includesSubSpaces {
            title =
                subSpaces.count == 1
                ? String(localized: "Delete “\(name)” and its Sub-Space?")
                : String(localized: "Delete “\(name)” and its \(subSpaces.count) Sub-Spaces?")
            message = String(
                localized: """
                    This permanently removes their tabs and browser data from Crest. Downloaded files you already \
                    saved are kept.
                    """)
            confirmation = String(localized: "Delete Spaces and Data")
            successors = []
            unlocking = nil
        } else {
            title = String(localized: "Delete “\(name)”?")
            message = String(
                localized: "Choose the Space that keeps \(name)’s sign-ins, history, passwords and pinned tabs.")
            confirmation = String(localized: "Delete \(name)")
            successors = subSpaces
            unlocking = space
        }
    }

    // MARK: - Actions - Deleting

    /// Deletes what the plan names through `browser`, handing a primary's
    /// group to `successor` when it goes alone: the whole group's Sub-Spaces
    /// first, then its primary. Throws the rule the core applied or why
    /// erasing failed, keeping what was not deleted yet.
    func run(in browser: BrowserStore, successor: UUID?, dataDeleter: any BrowserSpaceDataDeleting) async throws {
        guard let space = browser.spaceModel(request.spaceID) else { throw BrowserSpaceDeletionError.missingSpace }
        if request.includesSubSpaces {
            for member in browser.groupMembers(of: space) where member !== space {
                try await browser.deleteSpace(member.id, dataDeleter: dataDeleter)
            }
        }
        try await browser.deleteSpace(
            space.id, newPrimaryID: successors.isEmpty ? nil : successor ?? successors.first?.id,
            dataDeleter: dataDeleter)
    }
}
