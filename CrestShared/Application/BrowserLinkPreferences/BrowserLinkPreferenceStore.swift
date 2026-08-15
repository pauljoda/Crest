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

    func routingDecision(
        for url: URL,
        in session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID> = []
    ) -> BrowserLinkRoutingDecision {
        BrowserLinkRoutingPolicy.decision(
            for: url,
            preferences: preferences,
            session: session,
            unavailableSpaceIDs: unavailableSpaceIDs
        )
    }

    func rememberQuickWindowSpace(_ spaceID: SpaceID, for url: URL) {
        guard preferences.remembersQuickWindowSpaceBySite,
            let site = BrowserSavedSitePolicy.normalizedHost(url)
        else { return }
        update { $0.rememberedQuickWindowSpacesBySite[site] = spaceID }
    }

    func addRoute(destinationSpaceID: SpaceID) {
        update {
            $0.routes.append(
                BrowserLinkRoute(pattern: "", destinationSpaceID: destinationSpaceID)
            )
        }
    }

    func updateRoute(_ id: UUID, field: BrowserLinkRouteFieldUpdate) {
        update { preferences in
            guard let index = preferences.routes.firstIndex(where: { $0.id == id }) else {
                return
            }
            field.apply(to: &preferences.routes[index])
        }
    }

    func removeRoute(_ id: UUID) {
        update { $0.routes.removeAll { $0.id == id } }
    }

    func removeReferences(to spaceID: SpaceID) {
        update { preferences in
            preferences.routes.removeAll { $0.destinationSpaceID == spaceID }
            if preferences.externalLinkSpaceID == spaceID {
                preferences.externalLinkSpaceID = nil
            }
            preferences.rememberedQuickWindowSpacesBySite = preferences
                .rememberedQuickWindowSpacesBySite
                .filter { $0.value != spaceID }
        }
    }

    func moveRoute(_ id: UUID, by offset: Int) {
        update { preferences in
            guard let sourceIndex = preferences.routes.firstIndex(where: { $0.id == id }) else {
                return
            }
            let destinationIndex = sourceIndex + offset
            guard preferences.routes.indices.contains(destinationIndex) else { return }
            let route = preferences.routes.remove(at: sourceIndex)
            preferences.routes.insert(route, at: destinationIndex)
        }
    }

    func moveRoutes(fromOffsets: IndexSet, toOffset: Int) {
        update { preferences in
            let validOffsets = fromOffsets.filter(preferences.routes.indices.contains)
            let moving = validOffsets.map { preferences.routes[$0] }
            for index in validOffsets.sorted(by: >) {
                preferences.routes.remove(at: index)
            }
            let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
            let insertionIndex = min(
                max(toOffset - removedBeforeDestination, 0),
                preferences.routes.endIndex
            )
            preferences.routes.insert(contentsOf: moving, at: insertionIndex)
        }
    }
}
