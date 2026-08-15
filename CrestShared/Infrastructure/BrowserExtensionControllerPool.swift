import Foundation
import Observation

@Observable
@MainActor
final class BrowserExtensionControllerPool {
    @ObservationIgnored let tabWindowCoordinator: BrowserExtensionTabWindowCoordinator
    @ObservationIgnored let persistenceController: BrowserExtensionPersistenceController
    @ObservationIgnored let permissionController: BrowserExtensionPermissionController
    @ObservationIgnored let commandController: BrowserExtensionCommandController
    @ObservationIgnored let runtimeContextController: BrowserExtensionRuntimeContextController
    @ObservationIgnored let installationController: BrowserExtensionInstallationController
    @ObservationIgnored let restorationController: BrowserExtensionRestorationController
    @ObservationIgnored let toolbarController: BrowserExtensionToolbarController

    @ObservationIgnored private var commandSettingsHandler: ((BrowserExtensionCommandSettingsRoute, SpaceID) -> Void)?

    private(set) var actionRevision = 0

    /// The store-update scheduler, once a platform shell has supplied one.
    ///
    /// It is absent until then, exactly like the native-messaging handler:
    /// downloading and installing a replacement package is platform work, and
    /// a pool with no shell behind it has no business reaching the network.
    private(set) var updateModel: BrowserExtensionUpdateModel?

    var summariesBySpace: [SpaceID: [BrowserExtensionSummary]] {
        persistenceController.summariesBySpace
    }

    init(
        packageStore: any BrowserExtensionPackageStoring =
            BrowserExtensionPackageStore(),
        registry: BrowserExtensionRegistry = BrowserExtensionRegistry(),
        storedResourcePreparer:
            any BrowserExtensionStoredResourcePreparing =
            BrowserExtensionStoredResourceIdentityPreparer(),
        usesEphemeralWebKitStorage: Bool = true
    ) {
        let tabWindowCoordinator = BrowserExtensionTabWindowCoordinator()
        let persistenceController = BrowserExtensionPersistenceController(
            packageStore: packageStore,
            registry: registry
        )
        let permissionController = BrowserExtensionPermissionController(
            persistence: persistenceController
        )
        let commandController = BrowserExtensionCommandController(
            persistence: persistenceController
        )
        let runtimeContextController =
            BrowserExtensionRuntimeContextController(
                persistence: persistenceController,
                permissions: permissionController,
                contextObserver: BrowserExtensionContextObserver(),
                commandController: commandController,
                tabWindowCoordinator: tabWindowCoordinator,
                storedResourcePreparer: storedResourcePreparer,
                usesEphemeralWebKitStorage: usesEphemeralWebKitStorage
            )

        self.tabWindowCoordinator = tabWindowCoordinator
        self.persistenceController = persistenceController
        self.permissionController = permissionController
        self.commandController = commandController
        self.runtimeContextController = runtimeContextController
        installationController = BrowserExtensionInstallationController(
            persistence: persistenceController,
            runtime: runtimeContextController
        )
        restorationController = BrowserExtensionRestorationController(
            persistence: persistenceController,
            runtime: runtimeContextController
        )
        toolbarController = BrowserExtensionToolbarController(
            persistence: persistenceController,
            runtime: runtimeContextController,
            tabWindowCoordinator: tabWindowCoordinator
        )

        tabWindowCoordinator.actionDidUpdate = { [weak self] in
            self?.actionRevision &+= 1
        }
    }

    static func production(
        storedResourcePreparer:
            any BrowserExtensionStoredResourcePreparing =
            BrowserExtensionStoredResourceIdentityPreparer()
    ) -> BrowserExtensionControllerPool {
        BrowserExtensionControllerPool(
            packageStore: BrowserExtensionPackageStore.production(),
            registry: .production(),
            storedResourcePreparer: storedResourcePreparer,
            usesEphemeralWebKitStorage: false
        )
    }

    func setCommandSettingsHandler(
        _ handler:
            @escaping (
                BrowserExtensionCommandSettingsRoute,
                SpaceID
            ) -> Void
    ) {
        commandSettingsHandler = handler
    }

    func setNativeMessagingHandler(
        _ handler: BrowserExtensionNativeMessagingHandling?
    ) {
        tabWindowCoordinator.setNativeMessagingHandler(handler)
    }

    func setUpdateModel(_ model: BrowserExtensionUpdateModel?) {
        updateModel?.cancelScheduledUpdates()
        updateModel = model
    }

    func handleCommandSettingsRoute(
        _ route: BrowserExtensionCommandSettingsRoute,
        in spaceID: SpaceID
    ) -> Bool {
        guard let commandSettingsHandler else { return false }
        commandSettingsHandler(route, spaceID)
        return true
    }

    func recordActionMutations(_ count: Int = 1) {
        guard count > 0 else { return }
        actionRevision &+= count
    }
}
