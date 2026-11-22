import CloudKit
import Foundation

extension BrowserCloudSyncController {
    static func isolated(
        core: CrestCore,
        environment: BrowserLaunchEnvironment = .current,
        configuration: BrowserCloudSyncConfiguration? = .configured()
    ) -> BrowserCloudSyncController {
        guard let configuration = configuration?.isolated(for: environment),
            let profileID = environment.persistentIsolationID
        else {
            return BrowserCloudSyncController(
                core: core, configuration: nil, remoteService: nil, transportFactory: nil)
        }
        let controller = BrowserCloudSyncController(
            core: core, configuration: configuration,
            legacyState: .isolated(localProfileID: profileID, configuration: configuration),
            remoteService: CloudKitBrowserCloudSyncRemoteService(configuration: configuration),
            transportFactory: CloudKitBrowserCloudSyncTransportFactory(configuration: configuration, core: core)
        )
        controller.observeAccountChanges(named: .CKAccountChanged)
        return controller
    }
}
