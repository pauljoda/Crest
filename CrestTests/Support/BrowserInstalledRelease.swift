import Foundation

@testable import Crest

/// What an installed release before the core's session file left behind, for
/// the upgrade tests to carry.
enum BrowserInstalledRelease {
    /// Writes `session` the way such a release kept it: the session without
    /// history or images under its core key, each Space's history under a key
    /// of its own, and each open tab's image in `favicons`.
    static func write(_ session: BrowserSession, to defaults: UserDefaults, favicons: any BrowserFaviconStoring) throws
    {
        var core = BrowserCoreSessionAuthority.compact(session)
        for index in core.spaces.indices { core.spaces[index].history = [] }
        defaults.set(try JSONEncoder().encode(core), forKey: BrowserLegacySessionDefaults.coreKey)
        for space in session.spaces {
            defaults.set(
                try JSONEncoder().encode(space.history),
                forKey: BrowserLegacySessionDefaults.historyKeyPrefix + space.id.rawValue.uuidString)
            for tab in space.tabs { favicons.reconcile(tab.faviconData, tabID: tab.id) }
        }
    }

    /// The first session of a new file, as a launch gives it one when the
    /// installed release kept `session` whole with `journal`; the images its
    /// tabs carried land in `favicons`.
    @MainActor
    static func adopt(
        _ session: BrowserSession, journal: BrowserSyncJournal? = nil, into core: CrestCore,
        favicons: any BrowserFaviconStoring
    ) throws {
        try adopt(session, journalData: try journal?.encodedSnapshot(), into: core, favicons: favicons)
    }

    /// The first session of a new file, as `adopt(_:journal:into:favicons:)`
    /// gives it one, with the journal the installed release kept as `journalData`.
    @MainActor
    static func adopt(
        _ session: BrowserSession, journalData: Data?, into core: CrestCore, favicons: any BrowserFaviconStoring
    ) throws {
        let whole = try JSONEncoder().encode(session)
        let installed = LegacySession(core: nil, wholeGraph: whole, history: [], journal: journalData)
        for case .sessionAdopted(let adopted) in try core.send(AdoptLegacySession(installed: installed, seed: whole)) {
            for favicon in adopted.favicons { favicons.reconcile(favicon.image, tabID: TabID(rawValue: favicon.tabID)) }
        }
    }
}
