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

    /// Where an external link opens, or nil when it may open nowhere. The core
    /// owns the routing rule, including the locked-Space substitution: a link
    /// routed to a Space in `lockedSpaceIDs` never raises a prompt for another
    /// process, and opens in a Quick Window on an unlocked Space instead. A
    /// core that refuses the preferences opens the link nowhere rather than
    /// somewhere the rules did not choose.
    func routingDecision(
        for url: URL,
        in session: BrowserPresentedSession,
        unavailableSpaceIDs: Set<SpaceID> = [],
        lockedSpaceIDs: Set<SpaceID> = [],
        asking core: CrestCore
    ) -> BrowserLinkRoutingDecision? {
        let remembered = site(for: url, asking: core).flatMap { preferences.rememberedQuickWindowSpacesBySite[$0] }
        let routing = LinkRoutingPreferences(
            routes: preferences.routes.map(\.coreRoute),
            destination: preferences.externalLinkDestination,
            chosenSpaceID: preferences.externalLinkSpaceID?.rawValue,
            remembersSpaceBySite: preferences.remembersQuickWindowSpaceBySite, rememberedSpaceID: remembered?.rawValue)
        let context = LinkRoutingContext(
            spaces: session.spaces.map(\.id.rawValue), selectedSpaceID: session.selectedSpaceID.rawValue,
            unavailableSpaceIDs: unavailableSpaceIDs.map(\.rawValue))
        let route = ExternalLinkRoute(
            url: url.absoluteString, preferences: routing, context: context,
            lockedSpaceIDs: lockedSpaceIDs.map(\.rawValue))
        guard let placement = try? core.query(route), let spaceID = placement.spaceID.map(SpaceID.init(rawValue:))
        else { return nil }
        return placement.opensQuickWindow ? .quickWindow(spaceID: spaceID) : .space(spaceID)
    }

    func rememberQuickWindowSpace(_ spaceID: SpaceID, for url: URL, asking core: CrestCore) {
        guard let site = site(for: url, asking: core) else { return }
        update { $0.rememberedQuickWindowSpacesBySite[site] = spaceID }
    }

    /// The key a Quick Window remembers its Space under, or nil when the
    /// preference is off, the address has no host, or the core refuses it.
    private func site(for url: URL, asking core: CrestCore) -> String? {
        let site = QuickWindowSite(
            url: url.absoluteString, remembersSpaceBySite: preferences.remembersQuickWindowSpaceBySite)
        return (try? core.query(site))?.site
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
