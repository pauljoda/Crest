import CloudKit
import Foundation

extension BrowserCloudSyncController {
    static func isolated(
        browser: BrowserStore,
        environment: BrowserLaunchEnvironment = .current,
        configuration: BrowserCloudSyncConfiguration? = .configured()
    ) -> BrowserCloudSyncController {
        guard let configuration = configuration?.isolated(for: environment),
            let profileID = environment.persistentIsolationID,
            let defaults = UserDefaults(suiteName:
                BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(isolationID: profileID)
                    + ".cloud." + configuration.zoneName),
            let persistence = FileBrowserCloudSyncStatePersistence.isolated(
                localProfileID: profileID, configuration: configuration)
        else {
            return BrowserCloudSyncController(
                workflow: browser, configuration: nil,
                preferences: InMemoryBrowserCloudSyncPreferences(),
                remoteService: nil, transportFactory: nil
            )
        }
        let controller = BrowserCloudSyncController(
            workflow: browser, configuration: configuration,
            preferences: UserDefaultsBrowserCloudSyncPreferences(defaults: defaults, statePersistence: persistence),
            remoteService: CloudKitBrowserCloudSyncRemoteService(configuration: configuration),
            transportFactory: CloudKitBrowserCloudSyncTransportFactory(
                configuration: configuration, gateway: browser, persistence: persistence)
        )
        controller.observeAccountChanges(named: .CKAccountChanged)
        return controller
    }
}
