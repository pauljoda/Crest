import CrestCoreABI
import Foundation

/// TRANSITIONAL until session intents land: the persistent session the core
/// loaded from its file, taken over by the JSON session path with the native
/// read model Swift keeps beside it. Favicon bytes are native assets, so each
/// tab gets its image from the favicon store, by the tab it was loaded as.
@MainActor
struct BrowserCoreStoredSession {
    // MARK: - Types

    /// The core's answer: the session as loaded and repaired, where each
    /// repaired tab came from, and the selection an older release stored.
    private struct Projection: Decodable {
        let session: BrowserSession
        let assets: [Origin]
        let legacySelection: BrowserLegacySessionSelection?
    }

    private struct Origin: Decodable {
        let spaceIndex: Int
        let tabIndex: Int
        let sourceTabID: TabID
    }

    enum LoadError: Error {
        /// The core holds no session to take over.
        case noSession
        /// The core's projection could not be read.
        case unreadableProjection(Int32)
        /// A repaired tab names a position the session does not have.
        case invalidOrigin
    }

    // MARK: - Variables

    let authority: BrowserCoreSessionAuthority
    let sync: BrowserCoreSyncAuthority
    /// The selection an older release stored in the session, for the first
    /// window that has no record of its own.
    let legacySelection: BrowserLegacySessionSelection?

    // MARK: - Initializers

    /// Takes over the session `core` keeps, or answers nil when its file holds
    /// none yet. `legacySelection` stands in for the one the file stored when
    /// this launch migrated the session.
    static func load(
        core: CrestCore, favicons: any BrowserFaviconStoring, legacySelection: BrowserLegacySessionSelection? = nil
    ) throws -> BrowserCoreStoredSession? {
        guard let handles = core.storedSessionHandles() else { return nil }
        return try BrowserCoreStoredSession(handles: handles, favicons: favicons, legacySelection: legacySelection)
    }

    private init(
        handles: CrestCore.StoredSessionHandles, favicons: any BrowserFaviconStoring,
        legacySelection: BrowserLegacySessionSelection?
    ) throws {
        let projection: Projection
        do {
            defer { crest_session_release_command(handles.projection) }
            projection = try JSONDecoder().decode(Projection.self, from: Self.read(handles.projection))
        } catch {
            crest_sync_authority_release(handles.sync)
            crest_session_destroy(handles.session)
            throw error
        }
        let sync: BrowserCoreSyncAuthority
        do {
            sync = try BrowserCoreSyncAuthority(adopting: handles.sync)
        } catch {
            crest_session_destroy(handles.session)
            throw error
        }
        var session = projection.session
        for origin in projection.assets {
            guard session.spaces.indices.contains(origin.spaceIndex),
                session.spaces[origin.spaceIndex].tabs.indices.contains(origin.tabIndex)
            else {
                crest_session_destroy(handles.session)
                throw LoadError.invalidOrigin
            }
            var tab = session.spaces[origin.spaceIndex].tabs[origin.tabIndex]
            tab.faviconData = favicons.favicon(tabID: origin.sourceTabID)
            if tab.faviconData != nil, tab.faviconURL == nil { tab.faviconURL = tab.url }
            session.spaces[origin.spaceIndex].tabs[origin.tabIndex] = tab
        }
        authority = BrowserCoreSessionAuthority(
            adopting: handles.session, revision: handles.revision, projection: session)
        self.sync = sync
        self.legacySelection = legacySelection ?? projection.legacySelection
    }

    // MARK: - Actions - Reading

    private static func read(_ command: UInt64) throws -> Data {
        var length = 0
        let measured = crest_session_read_command(command, nil, 0, &length)
        guard measured == CREST_BUFFER_TOO_SMALL, length > 0 else { throw LoadError.unreadableProjection(measured) }
        let capacity = length
        var output = Data(count: capacity)
        let read = output.withUnsafeMutableBytes {
            crest_session_read_command(command, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
        }
        guard read == CREST_OK else { throw LoadError.unreadableProjection(read) }
        return output
    }
}
