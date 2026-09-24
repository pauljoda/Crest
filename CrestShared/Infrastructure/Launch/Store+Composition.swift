import Foundation
import CryptoKit

extension BrowserStore {
    static func production(
        launchEnvironment: BrowserLaunchEnvironment = .current,
        core: CrestCore = CrestCore()
    ) throws -> BrowserStore {
        // Keep the persistence boundary safe even if a future composition root
        // accidentally calls `production` for a fixture or preview launch.
        // Sample Spaces must never replace the installed session or be staged as
        // Cloud tombstones for the user's real Space IDs.
        if launchEnvironment.requiresIsolation {
            return try isolatedLaunch(launchEnvironment: launchEnvironment, core: core)
        }
        let storage = try transactionalStorage(legacy: UserDefaultsBrowserSessionPersistence(),
            journal: UserDefaultsBrowserSyncJournalPersistence(), isolationID: nil, environment: launchEnvironment)
        return production(persistence: storage, syncPersistence: storage.journalPersistence,
            credentialVault: KeychainCredentialVault(), core: core)
    }

    static func production(
        persistence: any BrowserSessionPersisting,
        syncPersistence: any BrowserSyncJournalPersisting,
        credentialVault: any CredentialVault,
        core: CrestCore = CrestCore()
    ) -> BrowserStore {
        let session = launchRepair(persistence.load() ?? .freshInstallSeed)
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: syncPersistence
        )
        let store = BrowserStore(
            session: session,
            selection: persistence.loadLegacySelection()?.launchSelection(in: session),
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            core: core
        )
        store.saveLaunchCheckpoint()
        store.beginInitialSyncStaging(session: store.session)
        return store
    }

    /// The core's checkpoint repair, accepted before any page is created or the
    /// session is saved. Launch cannot continue on an unaccepted repair;
    /// operational sync errors use the throwing bridge before commit.
    private static func launchRepair(_ session: BrowserSession) -> BrowserSession {
        do { return try BrowserCoreSync.repair(session) }
        catch { preconditionFailure("Core session repair failed before publication: \(error)") }
    }

    /// Saves the repaired launch session through a core checkpoint before any
    /// page exists. Repair may have changed what storage holds.
    func saveLaunchCheckpoint() {
        do { try family.save(session, to: persistence) }
        catch { localSyncErrorDescription = String(describing: error) }
    }

    /// Launch cleanup and retention, as the core's own `records.sweep` on this
    /// family's session, so its result reaches storage through a core
    /// checkpoint. No window is on screen yet, so every tab a stored window
    /// record shows is kept along with this store's own selection. It claims the
    /// family's sweep slot, so the first active scene does not repeat it.
    func sweepAtLaunch(keeping windows: [BrowserWindowState], now: Date = .now) {
        guard family.beginCleanupSweep(at: now) else { return }
        let kept = Set(windows.flatMap { $0.selection.tabSelections.values })
            .union(selection.tabSelections.values)
        guard
            family.executeRecords(
                .recordsSweep, arguments: BrowserSessionArguments.RecordsSweep(keepTabIds: kept.map(\.rawValue)),
                from: self, at: now)
        else { return }
        persist(deletionReason: .retention, scope: .everything)
    }

    static func preview() -> BrowserStore {
        BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
    }

    static func isolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment,
        core: CrestCore = CrestCore()
    ) throws -> BrowserStore {
        if let isolationID = launchEnvironment.persistentIsolationID {
            if let store = try persistentIsolatedLaunch(
                launchEnvironment: launchEnvironment,
                isolationID: isolationID,
                core: core
            ) {
                return store
            }
        }
        return inMemoryIsolatedLaunch(launchEnvironment: launchEnvironment, core: core)
    }

    private static func inMemoryIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment,
        core: CrestCore
    ) -> BrowserStore {
        let session = launchRepair(isolatedFixtureSession(for: launchEnvironment))
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence()
        )
        let store = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            syncCoordinator: syncCoordinator,
            core: core
        )
        store.saveLaunchCheckpoint()
        store.beginInitialSyncStaging(session: store.session)
        return store
    }

    private static func persistentIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment,
        isolationID: String,
        core: CrestCore
    ) throws -> BrowserStore? {
        let namespace = BrowserLaunchEnvironment.isolatedDefaultsSuiteName(
            isolationID: isolationID
        )
        guard let defaults = UserDefaults(suiteName: namespace) else { return nil }
        let legacy = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: InMemoryBrowserFaviconStore()
        )
        let persistence = try transactionalStorage(legacy: legacy,
            journal: InMemoryBrowserSyncJournalPersistence(), isolationID: isolationID, environment: launchEnvironment)
        let session = launchRepair(persistence.load() ?? isolatedFixtureSession(for: launchEnvironment))
        let syncCoordinator = BrowserSyncCoordinator(persistence: persistence.journalPersistence)
        let store = BrowserStore(
            session: session,
            selection: persistence.loadLegacySelection()?.launchSelection(in: session),
            persistence: persistence,
            credentialVault: KeychainCredentialVault(servicePrefix: namespace),
            syncCoordinator: syncCoordinator,
            core: core
        )
        store.saveLaunchCheckpoint()
        store.beginInitialSyncStaging(session: store.session)
        return store
    }

    private static func transactionalStorage(legacy: UserDefaultsBrowserSessionPersistence,
        journal: any BrowserSyncJournalPersisting, isolationID: String?,
        environment: BrowserLaunchEnvironment) throws -> BrowserTransactionalSessionPersistence {
        var storeURL: URL?
        do {
            var directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
                .appendingPathComponent("ControlPlane", isDirectory: true)
            if let isolationID {
                let namespace = SHA256.hash(data: Data(isolationID.utf8)).map { String(format: "%02x", $0) }.joined()
                directory = directory.appendingPathComponent("Isolated", isDirectory: true)
                    .appendingPathComponent(namespace, isDirectory: true)
            }
            let icons: any BrowserFaviconStoring
            if isolationID == nil {
                icons = BrowserFaviconFileStore.production() ?? InMemoryBrowserFaviconStore()
            } else {
                icons = BrowserFaviconFileStore(rootDirectory: directory.appendingPathComponent("Favicons", isDirectory: true))
            }
            storeURL = directory.appendingPathComponent("session.sqlite")
            return try migratedStorage(directory: directory, legacy: legacy, journal: journal,
                favicons: icons, environment: environment)
        } catch {
            throw BrowserSessionStartupFailure(storeURL: storeURL, underlying: error)
        }
    }

    /// Opens the core checkpoint under `directory` and, on the first launch that
    /// finds no checkpoint there, carries the installed release's defaults
    /// session and sync journal into it. The legacy values are left in place, so
    /// this is also the seam an upgrade test drives with its own directory,
    /// defaults suite and favicon store.
    static func migratedStorage(directory: URL, legacy: UserDefaultsBrowserSessionPersistence,
        journal: any BrowserSyncJournalPersisting, favicons: any BrowserFaviconStoring,
        environment: BrowserLaunchEnvironment) throws -> BrowserTransactionalSessionPersistence {
        let url = directory.appendingPathComponent("session.sqlite")
        do {
            let storage = try BrowserTransactionalSessionPersistence(url: url, favicons: favicons)
            try storage.migrateIfNeeded(session: migrationSession(legacy, storeURL: url),
                journal: journal.load(), legacySelection: legacy.loadLegacySelection())
            try BrowserSessionRecovery.prepareCloudRecovery(storeURL: url, environment: environment)
            try? storage.saveRecoveryCheckpoint()
            return storage
        } catch {
            throw BrowserSessionStartupFailure(storeURL: url, underlying: error)
        }
    }

    /// The installed release's session, or nil when this upgrade has none it may
    /// carry.
    ///
    /// A core that would not decode has already been copied aside by the legacy
    /// store, and those bytes are the only remaining record of that session.
    /// Migrating the disposable seed that stands in for it would let sync read
    /// the empty result as a deletion of every real Space, so the launch asks
    /// the cloud transport for a full pull instead: the seed is replaced by the
    /// Spaces CloudKit still holds rather than tombstoning them. Refusing to
    /// launch at all is not an option here — there is no checkpoint to restore
    /// on a first upgrade, so the retry would never succeed.
    private static func migrationSession(_ legacy: UserDefaultsBrowserSessionPersistence,
        storeURL: URL) throws -> BrowserSession? {
        let session = legacy.load()
        guard legacy.status != .preservedUnreadableSession else {
            try Data().write(to: BrowserSessionRecovery.cloudMarker(for: storeURL), options: .atomic)
            return nil
        }
        return session
    }

    private static func isolatedFixtureSession(
        for launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserSession {
        if launchEnvironment.requestsIsolatedCloudSync
            || launchEnvironment.forcesOnboardingWelcome
            || launchEnvironment.forcesMacOnboardingSetup
            || launchEnvironment.forcesMobileOnboardingSetup
        {
            return .freshInstallSeed
        }
        #if CREST_PERFORMANCE_HARNESS
            if let performanceSession = BrowserPerformanceSoakFixture.makeSession(
                baseURLString: launchEnvironment.performanceBaseURLString,
                rawTabCount: launchEnvironment.performanceTabCount,
                isHeavy: launchEnvironment.performanceHeavySession,
                runID: launchEnvironment.performanceRunID
            ) {
                return performanceSession
            }
        #endif
        return launchEnvironment.presentsShowcaseSession ? .showcase : .preview
    }

    static func privateBrowsing(core: CrestCore = CrestCore()) -> BrowserStore {
        BrowserStore(
            session: .privateBrowsing(),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: PrivateBrowsingCredentialVault(),
            browsingMode: .privateBrowsing,
            core: core
        )
    }
}
