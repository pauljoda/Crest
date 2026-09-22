import Foundation

/// Where an externally opened link may land when its routed Space is locked.
///
/// Any process on the machine can ask Crest to open a URL. Routing that link
/// into a locked Space would raise a biometric prompt the user never asked for,
/// from a window that is not even frontmost, and a wrong tap would unlock the
/// Space for whatever asked. So a locked destination is never unlocked on an
/// external link's behalf: the link opens in a Quick Window on a Space that is
/// already unlocked, and the user moves it themselves if that is what they want.
enum BrowserExternalLinkLockPolicy {
    struct Destination {
        let space: BrowserSpace
        /// True when the routed Space was locked and this is the substitute.
        let substitutesForLockedSpace: Bool
    }

    static func destination(
        routedTo spaceID: SpaceID,
        selectedSpaceID: SpaceID?,
        spaces: [BrowserSpace],
        unavailableSpaceIDs: Set<SpaceID> = [],
        isLocked: (BrowserSpace) -> Bool
    ) -> Destination? {
        guard let routed = spaces.first(where: { $0.id == spaceID }) else { return nil }
        guard isLocked(routed) else {
            return Destination(space: routed, substitutesForLockedSpace: false)
        }
        let candidates = spaces.filter {
            !isLocked($0) && !unavailableSpaceIDs.contains($0.id)
        }
        guard
            let substitute = candidates.first(where: { $0.id == selectedSpaceID })
                ?? candidates.first
        else { return nil }
        return Destination(space: substitute, substitutesForLockedSpace: true)
    }
}
