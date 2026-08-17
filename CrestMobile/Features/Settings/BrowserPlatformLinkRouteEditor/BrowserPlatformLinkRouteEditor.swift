import SwiftUI

struct BrowserPlatformLinkRouteEditor: View {
    let route: BrowserLinkRoute
    let spaces: [BrowserSpace]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let update: (BrowserLinkRouteFieldUpdate) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        BrowserPlatformLinkRouteEditorContent(
            route: route,
            spaces: spaces,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            update: update,
            delete: delete,
            moveUp: moveUp,
            moveDown: moveDown
        )
    }
}
