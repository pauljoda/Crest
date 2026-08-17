import SwiftUI

struct BrowserLinkRoutingSection: View {
    let routes: [BrowserLinkRoute]
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let updateRoute: (UUID, BrowserLinkRouteFieldUpdate) -> Void
    let remove: (UUID) -> Void
    let move: (UUID, Int) -> Void
    let add: (SpaceID) -> Void

    var body: some View {
        Section("Routing") {
            if routes.isEmpty {
                Text("No custom routes. Routes are evaluated from top to bottom before the default above.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                    BrowserPlatformLinkRouteEditor(
                        route: route,
                        spaces: spaces,
                        canMoveUp: index > 0,
                        canMoveDown: index + 1 < routes.count,
                        update: { field in updateRoute(route.id, field) },
                        delete: { remove(route.id) },
                        moveUp: { move(route.id, -1) },
                        moveDown: { move(route.id, 1) }
                    )
                }
            }

            Button("New Route", systemImage: "plus") {
                add(selectedSpaceID)
            }
            .buttonStyle(.crestTertiary)
        }
    }
}
