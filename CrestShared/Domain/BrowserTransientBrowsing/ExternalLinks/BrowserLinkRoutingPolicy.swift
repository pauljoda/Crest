import Foundation

enum BrowserLinkRoutingDecision: Equatable, Sendable {
    case quickWindow(spaceID: SpaceID)
    case space(SpaceID)

    var spaceID: SpaceID {
        switch self {
        case .quickWindow(let spaceID), .space(let spaceID):
            spaceID
        }
    }
}

enum BrowserLinkRoutingPolicy {
    static func decision(
        for url: URL,
        preferences: BrowserLinkPreferences,
        session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID> = []
    ) -> BrowserLinkRoutingDecision {
        if let route = matchingRoute(
            for: url,
            preferences: preferences,
            session: session,
            unavailableSpaceIDs: unavailableSpaceIDs
        ) {
            return .space(route.destinationSpaceID)
        }

        return defaultDecision(
            for: url,
            preferences: preferences,
            session: session,
            unavailableSpaceIDs: unavailableSpaceIDs
        )
    }

    private static func matchingRoute(
        for url: URL,
        preferences: BrowserLinkPreferences,
        session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID>
    ) -> BrowserLinkRoute? {
        preferences.routes.first {
            $0.isEnabled
                && isAvailable(
                    $0.destinationSpaceID,
                    in: session,
                    unavailableSpaceIDs: unavailableSpaceIDs
                )
                && matches($0, url: url)
        }
    }

    private static func defaultDecision(
        for url: URL,
        preferences: BrowserLinkPreferences,
        session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID>
    ) -> BrowserLinkRoutingDecision {
        switch preferences.externalLinkDestination {
        case .quickWindow:
            return quickWindowDecision(
                for: url,
                preferences: preferences,
                session: session,
                unavailableSpaceIDs: unavailableSpaceIDs
            )
        case .mostRecentSpace:
            return .space(
                fallbackSpaceID(
                    in: session,
                    unavailableSpaceIDs: unavailableSpaceIDs
                )
            )
        case .chosenSpace:
            return .space(
                existingChosenSpaceID(
                    preferences: preferences,
                    session: session,
                    unavailableSpaceIDs: unavailableSpaceIDs
                )
            )
        }
    }

    private static func quickWindowDecision(
        for url: URL,
        preferences: BrowserLinkPreferences,
        session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID>
    ) -> BrowserLinkRoutingDecision {
        let rememberedSpaceID = rememberedSpaceID(
            for: url,
            preferences: preferences,
            session: session,
            unavailableSpaceIDs: unavailableSpaceIDs
        )
        return .quickWindow(
            spaceID: rememberedSpaceID
                ?? fallbackSpaceID(
                    in: session,
                    unavailableSpaceIDs: unavailableSpaceIDs
                )
        )
    }

    private static func rememberedSpaceID(
        for url: URL,
        preferences: BrowserLinkPreferences,
        session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID>
    ) -> SpaceID? {
        guard preferences.remembersQuickWindowSpaceBySite,
            let site = BrowserSavedSitePolicy.normalizedHost(url),
            let spaceID = preferences.rememberedQuickWindowSpacesBySite[site],
            isAvailable(
                spaceID,
                in: session,
                unavailableSpaceIDs: unavailableSpaceIDs
            )
        else { return nil }
        return spaceID
    }

    private static func existingChosenSpaceID(
        preferences: BrowserLinkPreferences,
        session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID>
    ) -> SpaceID {
        guard let spaceID = preferences.externalLinkSpaceID,
            isAvailable(
                spaceID,
                in: session,
                unavailableSpaceIDs: unavailableSpaceIDs
            )
        else {
            return fallbackSpaceID(
                in: session,
                unavailableSpaceIDs: unavailableSpaceIDs
            )
        }
        return spaceID
    }

    private static func fallbackSpaceID(
        in session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID>
    ) -> SpaceID {
        if isAvailable(
            session.selectedSpaceID,
            in: session,
            unavailableSpaceIDs: unavailableSpaceIDs
        ) {
            return session.selectedSpaceID
        }
        return session.spaces.first {
            !unavailableSpaceIDs.contains($0.id)
        }?.id ?? session.selectedSpaceID
    }

    private static func isAvailable(
        _ spaceID: SpaceID,
        in session: BrowserSession,
        unavailableSpaceIDs: Set<SpaceID>
    ) -> Bool {
        !unavailableSpaceIDs.contains(spaceID)
            && session.space(id: spaceID) != nil
    }

    private static func matches(_ route: BrowserLinkRoute, url: URL) -> Bool {
        let pattern = route.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }
        let candidate = BrowserHistoryURL.normalized(url)?.absoluteString ?? url.absoluteString

        switch route.match {
        case .contains:
            return candidate.localizedCaseInsensitiveContains(pattern)
        case .exact:
            let normalizedPattern =
                URL(string: pattern).flatMap(BrowserHistoryURL.normalized)?
                .absoluteString ?? pattern
            return candidate.caseInsensitiveCompare(normalizedPattern) == .orderedSame
        }
    }
}
