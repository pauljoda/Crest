import SwiftUI

/// The identity a space-picking control needs: who the Space is, what it is called
/// right now, and which colour it owns.
///
/// It carries a whole `BrowserSpace` because the crest is rendered from the Space's
/// branding — flattening it to an id and a name would mean re-deriving the crest at
/// every call site. `displayName` exists for drafts whose name is still being typed
/// and for menus that want a phrase rather than a bare name.
struct CrestSpaceIdentity: Identifiable, Equatable {
    let space: BrowserSpace
    var displayName: String?
    var tintOverride: Color?

    var id: SpaceID { space.id }
    var name: String { displayName ?? space.name }
    var tint: Color { tintOverride ?? space.accent.color }

    init(space: BrowserSpace, displayName: String? = nil, tint: Color? = nil) {
        self.space = space
        self.displayName = displayName
        tintOverride = tint
    }

    static func list(_ spaces: [BrowserSpace]) -> [CrestSpaceIdentity] {
        spaces.map { CrestSpaceIdentity(space: $0) }
    }
}
