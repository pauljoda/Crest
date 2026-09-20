import Foundation
#if CREST_CORE_BACKED
import CryptoKit
#endif

extension BrowserStore {
    static func production(
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> BrowserStore {
        // Keep the persistence boundary safe even if a future composition root
        // accidentally calls `production` for a fixture or preview launch.
        // Sample Spaces must never replace the installed session or be staged as
        // Cloud tombstones for the user's real Space IDs.
        if BrowserLaunchIsolationPolicy.requiresIsolation(launchEnvironment) {
            return isolatedLaunch(launchEnvironment: launchEnvironment)
        }
        #if CREST_CORE_BACKED
        let storage = transactionalStorage(legacy: UserDefaultsBrowserSessionPersistence(),
            journal: UserDefaultsBrowserSyncJournalPersistence(), isolationID: nil)
        return production(persistence: storage, syncPersistence: storage.journalPersistence,
            credentialVault: KeychainCredentialVault())
        #else
        return production(
            persistence: UserDefaultsBrowserSessionPersistence(),
            syncPersistence: UserDefaultsBrowserSyncJournalPersistence(),
            credentialVault: KeychainCredentialVault()
        )
        #endif
    }

    static func production(
        persistence: any BrowserSessionPersisting,
        syncPersistence: any BrowserSyncJournalPersisting,
        credentialVault: any CredentialVault
    ) -> BrowserStore {
        var session = persistence.load() ?? .freshInstallSeed
        session.repairRuntimeIntegrity()
        session.cleanupCurrentTabsUsingSpacePreferences()
        session.applyDataRetentionPolicies()
        session.selectDefaultSpaceForLaunch()
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: syncPersistence
        )
        persistence.save(session)
        let store = BrowserStore(
            session: session,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator
        )
        store.beginInitialSyncStaging(session: session)
        return store
    }

    static func preview() -> BrowserStore {
        BrowserStore(session: .preview, persistence: InMemoryBrowserSessionPersistence())
    }

    static func isolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserStore {
        if let isolationID = launchEnvironment.persistentIsolationID {
            if let store = persistentIsolatedLaunch(
                launchEnvironment: launchEnvironment,
                isolationID: isolationID
            ) {
                return store
            }
        }
        return inMemoryIsolatedLaunch(launchEnvironment: launchEnvironment)
    }

    private static func inMemoryIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserStore {
        var session = isolatedFixtureSession(for: launchEnvironment)
        session.repairRuntimeIntegrity()
        session.cleanupCurrentTabsUsingSpacePreferences()
        session.applyDataRetentionPolicies()
        session.selectDefaultSpaceForLaunch()
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence()
        )
        let store = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            syncCoordinator: syncCoordinator
        )
        store.beginInitialSyncStaging(session: session)
        return store
    }

    private static func persistentIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment,
        isolationID: String
    ) -> BrowserStore? {
        let namespace = BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(
            isolationID: isolationID
        )
        guard let defaults = UserDefaults(suiteName: namespace) else { return nil }
        let legacy = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: InMemoryBrowserFaviconStore()
        )
        #if CREST_CORE_BACKED
        let persistence = transactionalStorage(legacy: legacy,
            journal: InMemoryBrowserSyncJournalPersistence(), isolationID: isolationID)
        #else
        let persistence = legacy
        #endif
        var session =
            persistence.load()
            ?? isolatedFixtureSession(for: launchEnvironment)
        session.repairRuntimeIntegrity()
        session.cleanupCurrentTabsUsingSpacePreferences()
        session.applyDataRetentionPolicies()
        session.selectDefaultSpaceForLaunch()
        persistence.save(session)
        #if CREST_CORE_BACKED
        let syncCoordinator = BrowserSyncCoordinator(persistence: persistence.journalPersistence)
        #else
        let syncCoordinator = BrowserSyncCoordinator(persistence: InMemoryBrowserSyncJournalPersistence())
        #endif
        let store = BrowserStore(
            session: session,
            persistence: persistence,
            credentialVault: KeychainCredentialVault(servicePrefix: namespace),
            syncCoordinator: syncCoordinator
        )
        store.beginInitialSyncStaging(session: session)
        return store
    }

    #if CREST_CORE_BACKED
    private static func transactionalStorage(legacy: UserDefaultsBrowserSessionPersistence,
        journal: any BrowserSyncJournalPersisting, isolationID: String?) -> BrowserTransactionalSessionPersistence {
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
            let storage = try BrowserTransactionalSessionPersistence(
                url: directory.appendingPathComponent("session.sqlite"), favicons: icons)
            try storage.migrateIfNeeded(session: migrationSession(legacy), journal: journal.load())
            return storage
        } catch {
            // Do not replace an unreadable database with seed data or stage
            // deletions from it. Recovery UI can safely use the preserved file.
            preconditionFailure("Cannot open the core session store: \(error)")
        }
    }
    private static func migrationSession(_ legacy: UserDefaultsBrowserSessionPersistence) throws -> BrowserSession? {
        let session = legacy.load()
        guard legacy.status != .preservedUnreadableSession else {
            throw BrowserTransactionalSessionPersistence.StorageError.invalidCheckpoint
        }
        return session
    }
    #endif

    private static func isolatedFixtureSession(
        for launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserSession {
        if launchEnvironment.forcesOnboardingWelcome
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

    static func privateBrowsing() -> BrowserStore {
        BrowserStore(
            session: .privateBrowsing(),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: PrivateBrowsingCredentialVault(),
            browsingMode: .privateBrowsing
        )
    }
}
