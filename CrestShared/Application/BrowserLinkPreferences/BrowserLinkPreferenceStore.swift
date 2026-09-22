import Foundation
import Observation

@Observable
@MainActor
final class BrowserLinkPreferenceStore {
    private(set) var preferences: BrowserLinkPreferences

    @ObservationIgnored private let persistence: any BrowserLinkPreferencesPersisting

    init(persistence: any BrowserLinkPreferencesPersisting) {
        self.persistence = persistence
        preferences = persistence.load() ?? .default
    }

    var focusesNewTabsOpenedFromLinks: Bool {
        get { preferences.focusesNewTabsOpenedFromLinks }
        set { update { $0.focusesNewTabsOpenedFromLinks = newValue } }
    }

    var followsTabsMovedToAnotherSpace: Bool {
        get { preferences.followsTabsMovedToAnotherSpace }
        set { update { $0.followsTabsMovedToAnotherSpace = newValue } }
    }

    var dragsLinksToPeek: Bool {
        get { preferences.dragsLinksToPeek }
        set { update { $0.dragsLinksToPeek = newValue } }
    }

    func update(_ update: (inout BrowserLinkPreferences) -> Void) {
        var revised = preferences
        update(&revised)
        guard revised != preferences else { return }
        preferences = revised
        persistence.save(revised)
    }

    func reset() {
        preferences = .default
        persistence.remove()
    }

    /// Where an external link opens. The core owns the routing rule; see
    /// `BrowserCorePolicy.linkRoutingDecision` for its fail-safe answer.
    func routingDecision(
        for url: URL,
        in session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID> = []
    ) -> BrowserLinkRoutingDecision {
        BrowserCorePolicy.linkRoutingDecision(
            for: url,
            preferences: preferences,
            session: session,
            unavailableSpaceIDs: unavailableSpaceIDs
        )
    }

    func rememberQuickWindowSpace(_ spaceID: SpaceID, for url: URL) {
        guard let site = BrowserCorePolicy.linkSite(
            for: url, remembersSpaceBySite: preferences.remembersQuickWindowSpaceBySite)
        else { return }
        update { $0.rememberedQuickWindowSpacesBySite[site] = spaceID }
    }

    // Route edits are core decisions applied to the stored preferences. An
    // edit the core refuses or cannot answer leaves them unchanged.

    func addRoute(destinationSpaceID: SpaceID) {
        guard let route = BrowserCorePolicy.createdLinkRoute(
            existing: preferences.routes, destinationSpaceID: destinationSpaceID)
        else { return }
        update { $0.routes.append(route) }
    }

    func updateRoute(_ id: UUID, field: BrowserLinkRouteFieldUpdate) {
        guard let route = preferences.routes.first(where: { $0.id == id }),
            let updated = BrowserCorePolicy.updatedLinkRoute(route, field: field)
        else { return }
        update { preferences in
            guard let index = preferences.routes.firstIndex(where: { $0.id == id }) else { return }
            preferences.routes[index] = updated
        }
    }

    func removeRoute(_ id: UUID) {
        guard let routes = BrowserCorePolicy.removingLinkRoute(id, from: preferences.routes) else { return }
        update { $0.routes = routes }
    }

    func moveRoute(_ id: UUID, by offset: Int) {
        guard let routes = BrowserCorePolicy.movingLinkRoute(id, by: offset, in: preferences.routes) else { return }
        update { $0.routes = routes }
    }

    /// The Space-deletion cascade: routes, the chosen Space and remembered
    /// Quick Window Spaces that point at a deleted Space.
    func removeReferences(to spaceID: SpaceID) {
        guard let revised = BrowserCorePolicy.linkPreferences(preferences, removingSpace: spaceID) else { return }
        update { $0 = revised }
    }
}
