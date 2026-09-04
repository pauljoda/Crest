import Foundation
import Observation

/// Which hosts each extension has framed, per Space, and therefore which
/// cookies stay rewritten.
///
/// Nothing here is persisted, deliberately. The relaxation is a consequence of
/// a live extension page framing a site; a fresh launch that never opens that
/// panel again should leave the jar alone, and a launch that does opens it
/// re-relaxes on the frame's first navigation. Persisting the list would keep
/// enforcing a rule for an extension that is no longer running.
///
/// The store is the only thing that knows a Space's full host set, so it — not
/// the cookie jar — decides what a change notification re-applies.
@Observable
@MainActor
final class BrowserExtensionCookieAccessStore: BrowserExtensionCookieAccessHandling {
    /// Bumped whenever the relaxed set changes, so a future settings surface
    /// can show what an extension has claimed without reading internals.
    private(set) var revision = 0

    @ObservationIgnored private let cookieJar: any BrowserExtensionCookieJarRelaxing
    @ObservationIgnored private var hostsByClient: [BrowserExtensionServiceClientID: Set<String>] = [:]
    @ObservationIgnored private var spacesByClient: [BrowserExtensionServiceClientID: SpaceID] = [:]
    @ObservationIgnored private var observedSpaces: Set<SpaceID> = []

    init(cookieJar: any BrowserExtensionCookieJarRelaxing) {
        self.cookieJar = cookieJar
    }

    /// Every host any client in `spaceID` still has relaxed.
    func relaxedHosts(in spaceID: SpaceID) -> Set<String> {
        var hosts: Set<String> = []
        for (client, clientSpace) in spacesByClient where clientSpace == spaceID {
            hosts.formUnion(hostsByClient[client] ?? [])
        }
        return hosts
    }

    /// The hosts one client has relaxed, in a stable order.
    func relaxedHosts(for client: BrowserExtensionServiceClientID) -> [String] {
        (hostsByClient[client] ?? []).sorted()
    }

    func relaxCookies(
        for host: String,
        client: BrowserExtensionServiceClientID,
        in spaceID: SpaceID
    ) async {
        let host = host.lowercased()
        guard !host.isEmpty else { return }
        spacesByClient[client] = spaceID
        if hostsByClient[client, default: []].insert(host).inserted {
            revision &+= 1
        }
        startObserving(spaceID)
        // Re-run even for a host already on the list. A frame reload is the
        // cheapest moment to notice a cookie the observer missed, and the jar
        // writes nothing when nothing has changed.
        await cookieJar.relax(host: host, in: spaceID)
    }

    func unregister(client: BrowserExtensionServiceClientID) {
        guard let spaceID = spacesByClient.removeValue(forKey: client) else { return }
        let hosts = hostsByClient.removeValue(forKey: client) ?? []
        if !hosts.isEmpty { revision &+= 1 }
        // Another extension in the same Space may still hold the same host, so
        // enforcement stops per Space rather than per client.
        guard relaxedHosts(in: spaceID).isEmpty else { return }
        observedSpaces.remove(spaceID)
        cookieJar.observe(spaceID: spaceID, onChange: nil)
    }

    private func startObserving(_ spaceID: SpaceID) {
        guard observedSpaces.insert(spaceID).inserted else { return }
        cookieJar.observe(spaceID: spaceID) { [weak self] in
            self?.reapply(in: spaceID)
        }
    }

    private func reapply(in spaceID: SpaceID) {
        let hosts = relaxedHosts(in: spaceID).sorted()
        guard !hosts.isEmpty else { return }
        Task { @MainActor [weak self] in
            for host in hosts {
                guard let self, self.observedSpaces.contains(spaceID) else { return }
                await self.cookieJar.relax(host: host, in: spaceID)
            }
        }
    }
}
