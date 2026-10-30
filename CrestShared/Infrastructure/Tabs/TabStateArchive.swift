import CryptoKit
import Dispatch
import Foundation
import os

final class BrowserTabStateArchive: BrowserTabStateArchiving, @unchecked Sendable {
    // MARK: - Types

    private struct StateKey: Hashable, Sendable {
        let profileID: UUID
        let tabID: UUID
    }

    /// What the write queue has yet to do for one tab's state.
    private enum StateWork: Sendable {
        case write(Data)
        case removal
    }

    private struct PendingEntry: Sendable {
        let order: UInt64
        let work: StateWork
    }

    /// What the write queue was asked and has yet to do, each ask stamped with
    /// its order, so finishing one leaves a later ask for the same tab noted.
    private struct PendingWork: Sendable {
        var states: [StateKey: PendingEntry] = [:]
        var profileRemovals: [UUID: UInt64] = [:]
        var lastOrder: UInt64 = 0
    }

    // MARK: - Static Variables

    /// One tab's framed state may not exceed this. A page with an enormous
    /// back/forward list is worth less than the disk and main-thread read it
    /// would cost, so it falls back to a plain reload.
    static let defaultMaximumStateByteCount = 4 * 1024 * 1024
    /// How many tabs one profile may keep state for. Beyond this the
    /// least-recently-written states are dropped.
    static let defaultMaximumStatesPerProfile = 100
    static let directoryName = "TabState"
    static let fileExtension = "webarchive-state"

    // MARK: - Variables

    let rootDirectory: URL

    private let maximumStateByteCount: Int
    private let maximumStatesPerProfile: Int
    private let writeQueue: DispatchQueue
    /// What the queue has yet to write or remove. A read answers from here
    /// before the file, so a state archived a moment ago is visible, and a
    /// read never waits behind the writes queued before it.
    private let pending = OSAllocatedUnfairLock(initialState: PendingWork())
    private let fileManager = FileManager.default

    // MARK: - Initializers

    init(
        rootDirectory: URL,
        maximumStateByteCount: Int = BrowserTabStateArchive.defaultMaximumStateByteCount,
        maximumStatesPerProfile: Int = BrowserTabStateArchive.defaultMaximumStatesPerProfile
    ) {
        precondition(maximumStateByteCount > 0)
        precondition(maximumStatesPerProfile > 0)
        self.rootDirectory = rootDirectory
        self.maximumStateByteCount = maximumStateByteCount
        self.maximumStatesPerProfile = maximumStatesPerProfile
        writeQueue = DispatchQueue(
            label: "com.pauldavis.crest.tab-state-archive",
            qos: .utility
        )
    }

    // MARK: - Actions - Locations

    /// The production archive, or nil when this process has no usable
    /// Application Support directory. A nil archive turns the feature off rather
    /// than failing a launch.
    static func production() -> BrowserTabStateArchive? {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else { return nil }
        return BrowserTabStateArchive(
            rootDirectory:
                applicationSupport
                .appendingPathComponent(
                    ProductIdentity.storageDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(directoryName, isDirectory: true)
        )
    }

    static func forLaunch(_ environment: BrowserLaunchEnvironment) -> BrowserTabStateArchive? {
        guard environment.requiresIsolation else { return production() }
        guard !environment.isXCTestRuntime, !environment.isSwiftUIPreviewRuntime,
            let identity = environment.persistentIsolationID,
            let base = production()?.rootDirectory
        else { return nil }
        let namespace = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return BrowserTabStateArchive(
            rootDirectory:
                base
                .appendingPathComponent("Isolated", isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true))
    }

    func directory(profileID: UUID) -> URL {
        rootDirectory.appendingPathComponent(profileID.uuidString, isDirectory: true)
    }

    func stateFileURL(profileID: UUID, tabID: UUID) -> URL {
        directory(profileID: profileID)
            .appendingPathComponent(tabID.uuidString)
            .appendingPathExtension(Self.fileExtension)
    }

    // MARK: - Actions - Reading

    /// What the archive was last asked to keep for the tab: the bytes the
    /// queue has yet to write, nothing while it has yet to remove them, or
    /// else the file. Files are written atomically, so the file is never
    /// half-written, and pruning and the profile limit remove only states no
    /// window is opening, so a read need not wait for the queue.
    func archivedState(profileID: UUID, tabID: UUID) -> Data? {
        let key = StateKey(profileID: profileID, tabID: tabID)
        let work = pending.withLock { pending -> StateWork? in
            if let entry = pending.states[key] { return entry.work }
            return pending.profileRemovals[profileID] == nil ? nil : .removal
        }
        switch work {
        case .write(let data): return data
        case .removal: return nil
        case nil: return try? Data(contentsOf: stateFileURL(profileID: profileID, tabID: tabID))
        }
    }

    // MARK: - Actions - Writing

    func archive(interactionState: Data, url: URL?, history: Data?, profileID: UUID, tabID: UUID) {
        guard !interactionState.isEmpty || history != nil else { return }
        var encoded = BrowserTabStateEnvelope(interactionState: interactionState, url: url, history: history).encoded()
        // The engine history matters most: past the limit the core's history
        // goes first, and the tab relaunches with what its engine kept.
        if encoded.count > maximumStateByteCount, history != nil, !interactionState.isEmpty {
            encoded = BrowserTabStateEnvelope(interactionState: interactionState, url: url).encoded()
        }
        guard encoded.count <= maximumStateByteCount else {
            // An oversized state must not leave an older, smaller one behind:
            // that stale state would restore a page the tab has moved past.
            removeState(profileID: profileID, tabID: tabID)
            return
        }
        let key = StateKey(profileID: profileID, tabID: tabID)
        let destination = stateFileURL(profileID: profileID, tabID: tabID)
        let directory = directory(profileID: profileID)
        let order = begin(.write(encoded), for: key)
        writeQueue.async { [self] in
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try? encoded.write(to: destination, options: .atomic)
            enforceProfileLimit(in: directory)
            finish(order, for: key)
        }
    }

    func removeState(profileID: UUID, tabID: UUID) {
        let key = StateKey(profileID: profileID, tabID: tabID)
        let url = stateFileURL(profileID: profileID, tabID: tabID)
        let order = begin(.removal, for: key)
        writeQueue.async { [self] in
            try? fileManager.removeItem(at: url)
            finish(order, for: key)
        }
    }

    func removeStates(profileID: UUID) {
        let directory = directory(profileID: profileID)
        // The removal supersedes every write and removal queued before it for
        // the profile's tabs; one asked after it is noted on its own.
        let order = pending.withLock { pending in
            pending.lastOrder += 1
            pending.states = pending.states.filter { $0.key.profileID != profileID }
            pending.profileRemovals[profileID] = pending.lastOrder
            return pending.lastOrder
        }
        writeQueue.async { [self] in
            try? fileManager.removeItem(at: directory)
            pending.withLock { pending in
                if pending.profileRemovals[profileID] == order { pending.profileRemovals[profileID] = nil }
            }
        }
    }

    func pruneStates(keeping tabIDsByProfileID: [UUID: Set<UUID>]) {
        writeQueue.async { [self] in
            for (profileID, tabIDs) in tabIDsByProfileID {
                let directory = directory(profileID: profileID)
                let retainedNames = Set(tabIDs.map(\.uuidString))
                for url in stateFiles(in: directory)
                where !retainedNames.contains(url.deletingPathExtension().lastPathComponent) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }

    func flushPendingWrites() async {
        await withCheckedContinuation { continuation in
            writeQueue.async {
                continuation.resume()
            }
        }
    }

    /// Notes `work` as what the queue will do for the tab, superseding what
    /// it was asked before, and answers the order it was asked in.
    private func begin(_ work: StateWork, for key: StateKey) -> UInt64 {
        pending.withLock { pending in
            pending.lastOrder += 1
            pending.states[key] = PendingEntry(order: pending.lastOrder, work: work)
            return pending.lastOrder
        }
    }

    /// The queue did what it was asked in `order` for the tab. A later ask
    /// for the same tab stays noted until its own turn.
    private func finish(_ order: UInt64, for key: StateKey) {
        pending.withLock { pending in
            if pending.states[key]?.order == order { pending.states[key] = nil }
        }
    }

    private func enforceProfileLimit(in directory: URL) {
        let files = stateFiles(in: directory)
        guard files.count > maximumStatesPerProfile else { return }
        let ordered =
            files
            .map { url in
                (
                    url: url,
                    modifiedAt:
                        (try? url.resourceValues(
                            forKeys: [.contentModificationDateKey]
                        ).contentModificationDate) ?? .distantPast
                )
            }
            .sorted { $0.modifiedAt < $1.modifiedAt }
        for entry in ordered.prefix(files.count - maximumStatesPerProfile) {
            try? fileManager.removeItem(at: entry.url)
        }
    }

    private func stateFiles(in directory: URL) -> [URL] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        return contents.filter { $0.pathExtension == Self.fileExtension }
    }
}
