import CloudKit
import Foundation

extension BrowserCloudSyncController {
    convenience init(
        browser: BrowserStore,
        configuration: BrowserCloudSyncConfiguration? = .configured(),
        defaults: UserDefaults? = nil,
        enabledKey: String = UserDefaultsBrowserCloudSyncPreferences.defaultEnabledKey
    ) {
        if defaults == nil,
            BrowserLaunchIsolationPolicy.requiresIsolation(.current)
        {
            self.init(
                workflow: browser,
                configuration: nil,
                preferences: InMemoryBrowserCloudSyncPreferences(),
                remoteService: nil,
                transportFactory: nil
            )
            return
        }
        let defaults = defaults ?? .standard
        let statePersistence: any BrowserCloudSyncStatePersisting =
            FileBrowserCloudSyncStatePersistence.production(
                migrationDefaults: defaults
            )
            ?? UserDefaultsBrowserCloudSyncStatePersistence(defaults: defaults)
        let preferences = UserDefaultsBrowserCloudSyncPreferences(
            defaults: defaults,
            enabledKey: enabledKey,
            statePersistence: statePersistence
        )
        let remoteService = configuration.map {
            CloudKitBrowserCloudSyncRemoteService(configuration: $0)
        }
        let transportFactory = configuration.map {
            CloudKitBrowserCloudSyncTransportFactory(
                configuration: $0,
                gateway: browser,
                persistence: statePersistence
            )
        }
        self.init(
            workflow: browser,
            configuration: configuration,
            preferences: preferences,
            remoteService: remoteService,
            transportFactory: transportFactory
        )
        observeAccountChanges(named: .CKAccountChanged)
    }
}
