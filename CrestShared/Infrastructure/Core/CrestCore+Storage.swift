import CrestCoreABI
import Foundation
import OSLog

extension CrestCore {
    // MARK: - Types

    /// Why a call that writes the session file failed.
    enum StorageError: Error, Equatable {
        /// The core could not write the file; nothing was published.
        case saveFailed
        /// The core would not read the session or journal it was given.
        case unreadable
        /// The file already holds a session, or the core keeps no file.
        case unavailable
    }

    /// TRANSITIONAL until session intents land: handles to the persistent
    /// session the core keeps, for the JSON session commands. The caller owns
    /// each one.
    struct StoredSessionHandles {
        let session: UInt64
        let revision: UInt64
        let sync: UInt64
        /// A command whose answer is the session as loaded and repaired.
        let projection: UInt64
    }

    // MARK: - Actions - Saves

    /// Returns once `revision` or a newer one is on disk, or once a save the
    /// core started itself has failed. Drains keep running while it waits, so
    /// the main actor stays free.
    func saved(through revision: Int64) async {
        guard state.savedRevision < revision else { return }
        await withCheckedContinuation { continuation in
            saveWaiters.append((revision, continuation))
        }
    }

    func resumeSaveWaiters() {
        let saved = state.savedRevision
        let ready = saveWaiters.filter { $0.revision <= saved }
        saveWaiters.removeAll { $0.revision <= saved }
        for waiter in ready { waiter.continuation.resume() }
    }

    /// A failed save surfaces through the handler and releases every waiter:
    /// the revisions they wait for stay pending until a later save succeeds.
    func storageFailed(_ reason: StorageFailure) {
        Logger(subsystem: "com.pauldavis.crest", category: "SessionStorage")
            .error("The core could not save the session: \(String(describing: reason), privacy: .public)")
        storageFailureHandler?(reason)
        let waiting = saveWaiters
        saveWaiters.removeAll()
        for waiter in waiting { waiter.continuation.resume() }
    }

    // MARK: - Actions - Stored session

    /// TRANSITIONAL until session intents land: the persistent session the
    /// core keeps, or nil when its file holds none yet.
    func storedSessionHandles() -> StoredSessionHandles? {
        var session: UInt64 = 0
        var revision: UInt64 = 0
        var sync: UInt64 = 0
        var projection: UInt64 = 0
        let status = crest_app_session(handle, &session, &revision, &sync, &projection)
        switch status {
        case CREST_OK:
            return StoredSessionHandles(session: session, revision: revision, sync: sync, projection: projection)
        case CREST_EMPTY:
            return nil
        default:
            Self.buildBug(status, "reach its stored session")
        }
    }

    /// TRANSITIONAL until the core migrates the legacy session itself (3b):
    /// writes the first session, in the stored format with each Space's
    /// history, and the journal that goes with it, in one transaction.
    func installSession(_ session: Data, journal: Data?) throws(StorageError) {
        let journal = journal ?? Data()
        let status = session.withUnsafeBytes { sessionBytes in
            journal.withUnsafeBytes { journalBytes in
                crest_app_install_session(
                    handle, sessionBytes.bindMemory(to: UInt8.self).baseAddress, session.count,
                    journalBytes.bindMemory(to: UInt8.self).baseAddress, journal.count)
            }
        }
        switch status {
        case CREST_OK: return
        case CREST_STORAGE_FAILED: throw .saveFailed
        case CREST_INVALID_STATE: throw .unavailable
        case CREST_INVALID_MESSAGE, CREST_INVALID_ARGUMENT, CREST_LIMIT_EXCEEDED: throw .unreadable
        default: Self.buildBug(status, "install the first session")
        }
    }
}
