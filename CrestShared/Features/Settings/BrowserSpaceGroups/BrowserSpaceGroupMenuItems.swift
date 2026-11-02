import SwiftUI

/// The menu items that start a Sub-Space of a Space, or move the Space into or
/// out of a group, each after the confirmation its change carries. Each group
/// it may join is listed by its primary, with that Space's crest.
struct BrowserSpaceGroupMenuItems: View {
    let browser: BrowserStore
    let space: SpaceModel
    let requestGroupChange: (BrowserSpaceGroupChange) -> Void
    /// Starts a Sub-Space after the Space named, where Settings opens it on
    /// its own page; elsewhere the window shows it.
    var addSubSpace: ((UUID) -> Void)? = nil

    var body: some View {
        if !browser.isPrivateBrowsing {
            Button("New Sub-Space", systemImage: "plus.square.on.square") {
                if let addSubSpace {
                    addSubSpace(space.id)
                } else if browser.addSubSpace(after: space.id) {
                    BrowserSpaceGroupNotices.formed()
                }
            }
            .disabled(browser.isDeleting(space.id))
        }
        if let separation = BrowserSpaceGroupChange.separating(space, in: browser) {
            Button(
                "Separate from “\(browser.primary(of: space).settings.name)”…",
                systemImage: "rectangle.portrait.and.arrow.right"
            ) { requestGroupChange(separation) }
        }
        if browser.canJoinGroup(space), !browser.joinableGroups(for: space).isEmpty {
            Menu("Make Sub-Space of", systemImage: "square.on.square") {
                ForEach(browser.joinableGroups(for: space)) { group in
                    Button {
                        if let join = BrowserSpaceGroupChange.joining(space, into: group, in: browser) {
                            requestGroupChange(join)
                        }
                    } label: {
                        BrowserSpaceIdentityLabel(space: group)
                    }
                }
                .crestMenuActionLabelStyle()
            }
        }
    }
}

/// The menu items that delete a Space, or a primary with its Sub-Spaces, each
/// after the confirmation its request's plan describes.
struct BrowserSpaceDeletionMenuItems: View {
    let browser: BrowserStore
    let space: SpaceModel
    let requestDeletion: (BrowserSpaceDeletionRequest) -> Void

    var body: some View {
        Button("Delete “\(space.settings.name)”…", systemImage: "trash", role: .destructive) {
            requestDeletion(BrowserSpaceDeletionRequest(spaceID: space.id))
        }
        .disabled(browser.spaceModels.count <= 1 || browser.isDeleting(space.id))
        if browser.leadsGroup(space) {
            Button("Delete “\(space.settings.name)” and Its Sub-Spaces…", systemImage: "trash", role: .destructive) {
                requestDeletion(BrowserSpaceDeletionRequest(spaceID: space.id, includesSubSpaces: true))
            }
            .disabled(browser.groupMembers(of: space).count >= browser.spaceModels.count)
        }
    }
}
