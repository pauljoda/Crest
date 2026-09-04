import Foundation
import Observation
import WebKit

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
    @ObservationIgnored let webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry

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
        webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry =
            BrowserExtensionWebpageMenuRegistry(),
        usesEphemeralWebKitStorage: Bool = true
    ) {
        let tabWindowCoordinator = BrowserExtensionTabWindowCoordinator(
            webpageMenuRegistry: webpageMenuRegistry
        )
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
        commandController.noteUserGesture = { [weak tabWindowCoordinator] context in
            tabWindowCoordinator?.noteUserGesture(for: context)
        }
        commandController.performSidebarCommand = { [weak tabWindowCoordinator] context, commandID in
            switch commandID {
            case "_execute_sidebar_action":
                return tabWindowCoordinator?.performSidebarAction(for: context, invocation: .sidebarCommand) == true
            case "_execute_action":
                return tabWindowCoordinator?.performSidebarAction(for: context, invocation: .action) == true
            default: return false
            }
        }
        let runtimeContextController =
            BrowserExtensionRuntimeContextController(
                persistence: persistenceController,
                permissions: permissionController,
                contextObserver: BrowserExtensionContextObserver(),
                commandController: commandController,
                tabWindowCoordinator: tabWindowCoordinator,
                webpageMenuRegistry: webpageMenuRegistry,
                storedResourcePreparer: storedResourcePreparer,
                usesEphemeralWebKitStorage: usesEphemeralWebKitStorage
            )

        self.tabWindowCoordinator = tabWindowCoordinator
        self.persistenceController = persistenceController
        self.permissionController = permissionController
        self.commandController = commandController
        self.runtimeContextController = runtimeContextController
        self.webpageMenuRegistry = webpageMenuRegistry
        installationController = BrowserExtensionInstallationController(
            persistence: persistenceController,
            runtime: runtimeContextController,
            webpageMenuRegistry: webpageMenuRegistry,
            storedResourcePreparer: storedResourcePreparer
        )
        restorationController = BrowserExtensionRestorationController(
            persistence: persistenceController,
            runtime: runtimeContextController
        )
        toolbarController = BrowserExtensionToolbarController(
            persistence: persistenceController,
            runtime: runtimeContextController,
            tabWindowCoordinator: tabWindowCoordinator,
            webpageMenuRegistry: webpageMenuRegistry
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

    /// A pool for a named isolated profile
    /// (`CREST_ISOLATED_PERSISTENCE_ID`).
    ///
    /// Such a profile persists its browser session and its WebKit storage, so
    /// its extensions have to persist too: WebKit hands the same website data
    /// store back on the next launch, and a pool that had forgotten the
    /// installation would leave that storage stranded and make every
    /// validation relaunch begin by re-adding the extension. Both records —
    /// the staged package and the registry entry — live under the same
    /// isolated name, never in the installed app's own state.
    ///
    /// `nil` when that name cannot be opened as a preferences domain, which
    /// leaves the caller to fall back to an ephemeral pool.
    static func isolated(
        isolationID: String,
        storedResourcePreparer:
            any BrowserExtensionStoredResourcePreparing =
            BrowserExtensionStoredResourceIdentityPreparer()
    ) -> BrowserExtensionControllerPool? {
        let suiteName = BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(
            isolationID: isolationID
        )
        guard let defaults = UserDefaults(suiteName: suiteName),
            let packageStore = BrowserExtensionPackageStore.isolated(
                isolationID: isolationID
            )
        else { return nil }
        return BrowserExtensionControllerPool(
            packageStore: packageStore,
            registry: .isolated(defaults: defaults),
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

    func setSidebarService(
        _ service: (any BrowserExtensionSidebarHandling)?,
        layoutSide: @escaping () -> String = { "right" }
    ) {
        tabWindowCoordinator.sidebarService = service
        tabWindowCoordinator.sidebarLayoutSide = layoutSide
    }

    func setTabGroupService(_ service: (any BrowserExtensionTabGroupHandling)?) {
        tabWindowCoordinator.tabGroupService = service
    }

    func setDeclarativeNetRequestService(
        _ service: (any BrowserExtensionDeclarativeNetRequestHandling)?
    ) {
        tabWindowCoordinator.declarativeNetRequestService = service
    }

    /// Installs the debugger session store and the consent gate in front of it.
    ///
    /// Both are supplied by the platform shell. Without a consent resolver no
    /// attachment is ever authorized, so a pool assembled for a test or a
    /// preview cannot silently grant page control.
    func setDebuggerService(
        _ service: (any BrowserExtensionDebuggerHandling)?,
        consent: (@MainActor (BrowserExtensionDebuggerIdentity) async -> Bool)? = nil
    ) {
        tabWindowCoordinator.debuggerService = service
        tabWindowCoordinator.debuggerConsent = consent
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

// MARK: - Installation

extension BrowserExtensionControllerPool {
    func loadExtension(
        at resourceBaseURL: URL,
        extensionID: String,
        in space: BrowserSpace,
        unsupportedAPIs: Set<String> = [],
        source: BrowserExtensionInstallationSource? = nil,
        permissionSnapshot: BrowserExtensionPermissionSnapshot = .empty
    ) async throws -> WKWebExtensionContext {
        try await installationController.loadExtension(
            at: resourceBaseURL,
            extensionID: extensionID,
            in: space,
            unsupportedAPIs: unsupportedAPIs,
            source: source,
            permissionSnapshot: permissionSnapshot
        )
    }

    @discardableResult
    func loadUnpackedExtension(
        from sourceURL: URL,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        try await installationController.loadUnpackedExtension(
            from: sourceURL,
            in: space
        )
    }

    func removeExtension(
        extensionID: String,
        from space: BrowserSpace
    ) async throws {
        try await installationController.removeExtension(
            extensionID: extensionID,
            from: space
        )
    }

    func deleteData(
        for space: BrowserSpace
    ) async throws -> BrowserSpaceDataReleaseProbe {
        try await installationController.deleteData(for: space)
    }
}

// MARK: - Permissions

extension BrowserExtensionControllerPool {
    func permissionDecision(
        for permission: String,
        extensionID: String,
        in spaceID: SpaceID
    ) -> BrowserExtensionAccessDecision {
        permissionController.permissionDecision(
            for: permission,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func hostDecision(
        for hostPattern: String,
        extensionID: String,
        in spaceID: SpaceID
    ) -> BrowserExtensionAccessDecision {
        permissionController.hostDecision(
            for: hostPattern,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func setPermissionDecision(
        _ decision: BrowserExtensionAccessDecision,
        for permission: String,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        permissionController.setPermissionDecision(
            decision,
            for: permission,
            extensionID: extensionID,
            in: spaceID,
            context: loadedContext(
                extensionID: extensionID,
                in: spaceID
            ),
            nativeMessagingCapability:
                runtimeContextController.nativeMessagingCapability
        )
    }

    func setPermissionDecision(
        _ decision: BrowserExtensionAccessDecision,
        for permission: String,
        extensionID: String,
        in space: BrowserSpace
    ) async throws {
        let previous = permissionDecision(
            for: permission,
            extensionID: extensionID,
            in: space.id
        )
        guard previous != decision else { return }
        setPermissionDecision(
            decision,
            for: permission,
            extensionID: extensionID,
            in: space.id
        )
        try await restorationController.restartEnabledExtension(
            extensionID: extensionID,
            in: space
        )
    }

    func setHostDecision(
        _ decision: BrowserExtensionAccessDecision,
        for hostPattern: String,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        permissionController.setHostDecision(
            decision,
            for: hostPattern,
            extensionID: extensionID,
            in: spaceID,
            context: loadedContext(
                extensionID: extensionID,
                in: spaceID
            ),
            nativeMessagingCapability:
                runtimeContextController.nativeMessagingCapability
        )
    }

    func setHostDecision(
        _ decision: BrowserExtensionAccessDecision,
        for hostPattern: String,
        extensionID: String,
        in space: BrowserSpace
    ) async throws {
        let previous = hostDecision(
            for: hostPattern,
            extensionID: extensionID,
            in: space.id
        )
        guard previous != decision else { return }
        setHostDecision(
            decision,
            for: hostPattern,
            extensionID: extensionID,
            in: space.id
        )
        try await restorationController.restartEnabledExtension(
            extensionID: extensionID,
            in: space
        )
    }

    func persistPermissionState(
        extensionID: String,
        in spaceID: SpaceID
    ) {
        runtimeContextController.persistPermissionState(
            extensionID: extensionID,
            in: spaceID
        )
    }
}

// MARK: - Restoration

extension BrowserExtensionControllerPool {
    func restoreEnabledExtensions(in spaces: [BrowserSpace]) async {
        await restorationController.restoreEnabledExtensions(in: spaces)
    }

    func setExtensionEnabled(
        _ enabled: Bool,
        extensionID: String,
        in space: BrowserSpace
    ) async throws {
        try await restorationController.setExtensionEnabled(
            enabled,
            extensionID: extensionID,
            in: space
        )
    }
}

// MARK: - Runtime Context

extension BrowserExtensionControllerPool {
    func controller(for space: BrowserSpace) -> WKWebExtensionController {
        runtimeContextController.controller(for: space)
    }

    func loadedContext(
        extensionID: String,
        in spaceID: SpaceID
    ) -> WKWebExtensionContext? {
        runtimeContextController.loadedContext(
            extensionID: extensionID,
            in: spaceID
        )
    }

    func extensionPageConfiguration(
        for extensionURL: URL,
        in spaceID: SpaceID
    ) -> BrowserExtensionPageConfiguration? {
        runtimeContextController.extensionPageConfiguration(
            for: extensionURL,
            in: spaceID
        )
    }

    func replaceExtensionPageNavigation(
        _ url: URL,
        tabID: TabID,
        spaceID: SpaceID
    ) -> Bool {
        tabWindowCoordinator.replaceExtensionPageNavigation(
            url,
            tabID: tabID,
            spaceID: spaceID
        )
    }

    func extensions(
        in spaceID: SpaceID
    ) -> [BrowserExtensionSummary] {
        persistenceController.extensions(
            in: spaceID,
            nativeMessagingCapability:
                runtimeContextController.nativeMessagingCapability
        )
    }

    /// Every `externally_connectable.matches` pattern authored by an extension
    /// loaded in `spaceID`, sorted so a page's script is stable across launches.
    /// Web pages matching one of them receive the page-world `chrome.runtime`
    /// alias over WebKit's `browser.runtime`.
    func externallyConnectableMatchPatterns(in spaceID: SpaceID) -> [String] {
        Set(
            runtimeContextController.contexts(in: spaceID).values.flatMap {
                BrowserExtensionExternallyConnectablePolicy.matchPatterns(
                    in: $0.webExtension.manifest
                )
            }
        ).sorted()
    }
}

// MARK: - Toolbar

extension BrowserExtensionControllerPool {
    func setPinned(
        _ pinned: Bool,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        guard
            toolbarController.setPinned(
                pinned,
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        recordActionMutations()
    }
}

// MARK: - Updates

extension BrowserExtensionControllerPool {
    /// Every Chrome Web Store installation across every Space, as update
    /// targets.
    ///
    /// The registry is the source of truth for provenance: a row only appears
    /// here when it recorded a `chromeWebStore` source at install time, which
    /// is also the row that carries the verified extension identity and
    /// publisher-key hash a replacement must match.
    func chromeWebStoreUpdateTargets() -> [BrowserExtensionUpdateTarget] {
        persistenceController.installations.compactMap { installation in
            guard case .chromeWebStore(let source) = installation.source,
                source.extensionID.rawValue == installation.id
            else {
                return nil
            }
            return BrowserExtensionUpdateTarget(
                extensionID: installation.id,
                spaceID: installation.spaceID,
                displayName: installation.displayName,
                installedVersion: installation.version,
                isEnabled: installation.isEnabled
            )
        }
    }

    /// Arms the update cadence once launch restoration has settled.
    func startExtensionUpdatesIfNeeded() {
        updateModel?.scheduleCheckIfNeeded()
    }
}
