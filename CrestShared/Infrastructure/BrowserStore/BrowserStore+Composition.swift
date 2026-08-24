import Foundation

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
        let persistence = UserDefaultsBrowserSessionPersistence()
        var session = persistence.load() ?? .freshInstallSeed
        session.repairRuntimeIntegrity()
        session.cleanupCurrentTabsUsingSpacePreferences()
        session.applyDataRetentionPolicies()
        session.selectDefaultSpaceForLaunch()
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: UserDefaultsBrowserSyncJournalPersistence()
        )
        var initialSyncErrorDescription: String?
        if !session.hasDisposableSeedState {
            do {
                try syncCoordinator.stage(session: session, deletionReason: .retention)
            } catch {
                // Local browsing remains available when the journal cannot be written.
                // The session remains authoritative and will be staged again next launch.
                initialSyncErrorDescription = String(describing: error)
            }
        }
        persistence.save(session)
        let store = BrowserStore(
            session: session,
            persistence: persistence,
            credentialVault: KeychainCredentialVault(),
            syncCoordinator: syncCoordinator
        )
        store.localSyncErrorDescription = initialSyncErrorDescription
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
        _ = try? syncCoordinator.stage(
            session: session,
            deletionReason: .retention
        )
        return BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            syncCoordinator: syncCoordinator
        )
    }

    private static func persistentIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment,
        isolationID: String
    ) -> BrowserStore? {
        let namespace = "\(ProductIdentity.serviceNamespace).isolated.\(isolationID)"
        guard let defaults = UserDefaults(suiteName: namespace) else { return nil }
        let persistence = UserDefaultsBrowserSessionPersistence(
            defaults: defaults,
            faviconStore: InMemoryBrowserFaviconStore()
        )
        var session = persistence.load()
            ?? isolatedFixtureSession(for: launchEnvironment)
        session.repairRuntimeIntegrity()
        session.cleanupCurrentTabsUsingSpacePreferences()
        session.applyDataRetentionPolicies()
        session.selectDefaultSpaceForLaunch()
        persistence.save(session)
        let syncCoordinator = BrowserSyncCoordinator(
            persistence: InMemoryBrowserSyncJournalPersistence()
        )
        _ = try? syncCoordinator.stage(
            session: session,
            deletionReason: .retention
        )
        return BrowserStore(
            session: session,
            persistence: persistence,
            credentialVault: KeychainCredentialVault(servicePrefix: namespace),
            syncCoordinator: syncCoordinator
        )
    }

    private static func isolatedFixtureSession(
        for launchEnvironment: BrowserLaunchEnvironment
    ) -> BrowserSession {
        #if CREST_PERFORMANCE_HARNESS
            if let performanceSession = BrowserPerformanceSoakFixture.makeSession(
                baseURLString: launchEnvironment.performanceBaseURLString,
                rawTabCount: launchEnvironment.performanceTabCount,
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
