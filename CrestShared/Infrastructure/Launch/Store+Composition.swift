import CryptoKit
import Foundation

extension BrowserStore {
    /// The store of this launch's session. A launch that needs isolation keeps
    /// its own directory or a fixture in memory. Otherwise the core's file
    /// holds the session, carried once from the release before it.
    static func production(core: CrestCore, launchEnvironment: BrowserLaunchEnvironment = .current) throws
        -> BrowserStore
    {
        // Keep the persistence boundary safe even if a future composition root
        // accidentally calls `production` for a fixture or preview launch.
        // Sample Spaces must never replace the installed session or be staged as
        // Cloud tombstones for the user's real Space IDs.
        if launchEnvironment.requiresIsolation {
            return try isolatedLaunch(core: core, launchEnvironment: launchEnvironment)
        }
        let favicons: any BrowserFaviconStoring = BrowserFaviconFileStore.production() ?? InMemoryBrowserFaviconStore()
        let stored = try migratedStorage(
            core: core, legacy: .installed, favicons: favicons, seed: .freshInstallSeed, environment: launchEnvironment)
        return production(stored: stored, core: core, favicons: favicons, credentialVault: KeychainCredentialVault())
    }

    /// The store over the session the core loaded. Its sync component is the
    /// core's own, which staged the loaded session and saves every journal it
    /// accepts with the session.
    static func production(
        stored: BrowserCoreStoredSession, core: CrestCore, favicons: any BrowserFaviconStoring,
        credentialVault: any CredentialVault
    ) -> BrowserStore {
        let family = BrowserStoreFamily(stored: stored, storage: core, favicons: favicons)
        return BrowserStore(
            credentialVault: credentialVault,
            syncCoordinator: BrowserSyncCoordinator(core: stored.sync),
            browsingMode: .standard,
            family: family,
            core: core
        )
    }

    /// The core's checkpoint repair, accepted before any page is created.
    /// Launch cannot continue on an unaccepted repair; operational sync errors
    /// use the throwing bridge before commit.
    private static func launchRepair(_ session: BrowserSession) -> BrowserSession {
        do { return try BrowserCoreSync.repair(session) } catch {
            preconditionFailure("Core session repair failed before publication: \(error)")
        }
    }

    /// Launch cleanup and retention: the core sweeps this family's session
    /// before any scene is on screen, keeping every tab an open window shows
    /// and every tab a saved window's record shows. The core remembers the
    /// sweep, so the first active scene does not repeat it.
    func sweepAtLaunch() {
        sweepExpiredBrowsingData()
    }

    static func preview() -> BrowserStore {
        BrowserStore(session: .preview)
    }

    static func isolatedLaunch(core: CrestCore, launchEnvironment: BrowserLaunchEnvironment) throws -> BrowserStore {
        if let isolationID = launchEnvironment.persistentIsolationID,
            let store = try persistentIsolatedLaunch(
                core: core, launchEnvironment: launchEnvironment, isolationID: isolationID)
        {
            return store
        }
        return inMemoryIsolatedLaunch(launchEnvironment: launchEnvironment, core: core)
    }

    private static func inMemoryIsolatedLaunch(
        launchEnvironment: BrowserLaunchEnvironment,
        core: CrestCore
    ) -> BrowserStore {
        let session = launchRepair(isolatedFixtureSession(for: launchEnvironment))
        return BrowserStore(
            session: session,
            credentialVault: InMemoryCredentialVault(),
            syncCoordinator: BrowserSyncCoordinator(persistence: InMemoryBrowserSyncJournalPersistence()),
            core: core
        )
    }

    private static func persistentIsolatedLaunch(
        core: CrestCore, launchEnvironment: BrowserLaunchEnvironment, isolationID: String
    ) throws -> BrowserStore? {
        let namespace = BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID)
        guard let directory = core.storageDirectory, let defaults = UserDefaults(suiteName: namespace) else {
            return nil
        }
        let favicons = BrowserFaviconFileStore(
            rootDirectory: directory.appendingPathComponent("Favicons", isDirectory: true))
        let stored = try migratedStorage(
            core: core, legacy: BrowserLegacySessionDefaults(defaults: defaults, journalDefaults: []),
            favicons: favicons, seed: isolatedFixtureSession(for: launchEnvironment), environment: launchEnvironment)
        return production(
            stored: stored, core: core, favicons: favicons,
            credentialVault: KeychainCredentialVault(servicePrefix: namespace))
    }

    /// Where the core keeps this launch's session file: the installed app's
    /// directory, or the one a persistent review launch keeps apart from it.
    /// Nil keeps the session in memory.
    static func sessionDirectory(for launchEnvironment: BrowserLaunchEnvironment) throws -> URL? {
        let isolationID = launchEnvironment.persistentIsolationID
        guard !launchEnvironment.requiresIsolation || isolationID != nil else { return nil }
        var directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
        .appendingPathComponent("ControlPlane", isDirectory: true)
        if launchEnvironment.requiresIsolation, let isolationID {
            let namespace = SHA256.hash(data: Data(isolationID.utf8)).map { String(format: "%02x", $0) }.joined()
            directory = directory.appendingPathComponent("Isolated", isDirectory: true)
                .appendingPathComponent(namespace, isDirectory: true)
        }
        return directory
    }

    /// The one core this launch creates, keeping its session in
    /// `sessionDirectory(for:)`. A file the core cannot use is a startup
    /// failure the recovery screen answers.
    static func launchCore(for launchEnvironment: BrowserLaunchEnvironment) throws -> CrestCore {
        let directory: URL?
        do { directory = try sessionDirectory(for: launchEnvironment) } catch {
            throw BrowserSessionStartupFailure(storageDirectory: nil, underlying: error)
        }
        do { return try CrestCore(configuration: AppConfiguration(storageDirectory: directory?.path)) } catch {
            throw BrowserSessionStartupFailure(storageDirectory: directory, underlying: error)
        }
    }

    /// Takes over the session `core` keeps. On the first launch whose file
    /// holds none, the core carries the installed release's defaults session,
    /// history and sync journal into the file, or installs `seed` when there is
    /// nothing it can carry; the images that session held inside its tabs land
    /// in `favicons`. The legacy values are left in place, so this is also the
    /// seam an upgrade test drives with its own directory, defaults suite and
    /// favicon store.
    static func migratedStorage(
        core: CrestCore, legacy: BrowserLegacySessionDefaults, favicons: any BrowserFaviconStoring,
        seed: @autoclosure () -> BrowserSession, environment: BrowserLaunchEnvironment
    ) throws -> BrowserCoreStoredSession {
        guard let directory = core.storageDirectory else {
            preconditionFailure("A core that keeps nothing on disk has no stored session to open.")
        }
        do {
            if let stored = try BrowserCoreStoredSession.load(core: core, favicons: favicons) {
                try BrowserSessionRecovery.prepareCloudRecovery(in: directory, environment: environment)
                return stored
            }
            let adoption = AdoptLegacySession(installed: legacy.values, seed: try JSONEncoder().encode(seed()))
            for case .sessionAdopted(let adopted) in try core.send(adoption) {
                for favicon in adopted.favicons {
                    favicons.reconcile(favicon.image, tabID: TabID(rawValue: favicon.tabID))
                }
            }
            try BrowserSessionRecovery.prepareCloudRecovery(in: directory, environment: environment)
            guard let stored = try BrowserCoreStoredSession.load(core: core, favicons: favicons) else {
                throw BrowserCoreStoredSession.LoadError.noSession
            }
            return stored
        } catch {
            throw BrowserSessionStartupFailure(storageDirectory: directory, underlying: error)
        }
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
            credentialVault: PrivateBrowsingCredentialVault(),
            browsingMode: .privateBrowsing,
            core: core
        )
    }
}
