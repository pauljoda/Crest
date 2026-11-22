import CloudKit
import Foundation

extension BrowserCloudSyncController {
    convenience init(
        core: CrestCore,
        configuration: BrowserCloudSyncConfiguration? = .configured(),
        defaults: UserDefaults? = nil
    ) {
        if defaults == nil,
            BrowserLaunchEnvironment.current.requiresIsolation
        {
            self.init(
                core: core,
                configuration: nil,
                remoteService: nil,
                transportFactory: nil
            )
            return
        }
        let defaults = defaults ?? .standard
        let remoteService = configuration.map {
            CloudKitBrowserCloudSyncRemoteService(configuration: $0)
        }
        let transportFactory = configuration.map {
            CloudKitBrowserCloudSyncTransportFactory(
                configuration: $0,
                core: core
            )
        }
        self.init(
            core: core,
            configuration: configuration,
            legacyState: .production(defaults: defaults),
            remoteService: remoteService,
            transportFactory: transportFactory
        )
        observeAccountChanges(named: .CKAccountChanged)
    }
}
