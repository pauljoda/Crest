import Dispatch
import Foundation

/// Stores per-tab `WKWebView.interactionState` blobs so a tab that lost its web
/// view — to residency trimming, to a relaunch — comes back with its
/// back/forward list and scroll positions instead of a bare reload.
///
/// Blobs run to hundreds of kilobytes, so they are kept out of the session JSON
/// and written as one file per tab, off the main thread. Nothing here decides
/// *whether* a tab may be archived: private and disposable runtimes are given no
/// archive at all, so they cannot write one by accident.
protocol BrowserTabStateArchiving: AnyObject, Sendable {
    /// The framed envelope stored for one tab, or nil when there is none.
    func archivedState(profileID: UUID, tabID: TabID) -> Data?
    func archive(interactionState: Data, url: URL?, profileID: UUID, tabID: TabID)
    func removeState(profileID: UUID, tabID: TabID)
    /// Drops every state belonging to one profile. Space deletion calls this, so
    /// per-Space isolation survives a Space being deleted.
    func removeStates(profileID: UUID)
    /// Drops states for tabs a profile no longer has, current or archived.
    /// Profiles absent from the map are left untouched.
    func pruneStates(keeping tabIDsByProfileID: [UUID: Set<TabID>])
    func flushPendingWrites() async
}
