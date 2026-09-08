import Foundation

/// The cookie jar double, shipped in the app target so tests, previews, and a
/// pool assembled without a platform shell all use the same seam.
///
/// It records the rewrite requests rather than performing one, and exposes a
/// way to stand in for the site re-setting a `SameSite` cookie.
@MainActor
final class InMemoryBrowserExtensionCookieJar: BrowserExtensionCookieJarRelaxing {
    /// Every `relax` call in arrival order, per Space.
    private(set) var relaxRequests: [SpaceID: [String]] = [:]
    private(set) var synchronizedHosts: [SpaceID: Set<String>] = [:]

    private var observers: [SpaceID: @MainActor () -> Void] = [:]

    init() {}

    var observedSpaces: Set<SpaceID> { Set(observers.keys) }

    func relaxedHosts(in spaceID: SpaceID) -> Set<String> {
        Set(relaxRequests[spaceID] ?? [])
    }

    func relax(host: String, in spaceID: SpaceID) async {
        relaxRequests[spaceID, default: []].append(host)
    }

    func setSynchronizedHosts(_ hosts: Set<String>, in spaceID: SpaceID) {
        synchronizedHosts[spaceID] = hosts
    }

    func observe(spaceID: SpaceID, onChange: (@MainActor () -> Void)?) {
        observers[spaceID] = onChange
    }

    /// Stands in for a third-party write to the jar, the way a login response
    /// re-setting a `Lax` session cookie would.
    func simulateCookieChange(in spaceID: SpaceID) {
        observers[spaceID]?()
    }
}
