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
        Section {
            if routes.isEmpty {
                Text("No routes yet. Add a URL rule to open matching links in a specific Space.")
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
            .buttonStyle(.bordered)
        } header: {
            Text("Routing")
        } footer: {
            Text("The first matching route wins. Other links use your default destination.")
        }
        .containerValue(\.settingsFullWidth, true)
    }
}
