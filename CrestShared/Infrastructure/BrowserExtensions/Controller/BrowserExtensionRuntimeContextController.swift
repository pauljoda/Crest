import Foundation
import WebKit

@MainActor
final class BrowserExtensionRuntimeContextController {
    private static let customURLSchemeRegistration: Void = {
        WKWebExtension.MatchPattern.registerCustomURLScheme(
            BrowserExtensionRuntimeIdentifierPolicy.urlScheme
        )
    }()

    private struct ControllerEntry {
        let profileID: UUID
        let controller: WKWebExtensionController
    }

    private var controllerEntries: [SpaceID: ControllerEntry] = [:]
    private var contextsBySpace: [SpaceID: [String: WKWebExtensionContext]] = [:]
    private var runtimeResourceAccess: [SpaceID: [String: AnyObject]] = [:]

    private let persistence: BrowserExtensionPersistenceController
    private let permissions: BrowserExtensionPermissionController
    private let contextObserver: BrowserExtensionContextObserver
    private let commandController: BrowserExtensionCommandController
    private let tabWindowCoordinator: BrowserExtensionTabWindowCoordinator
    private let storedResourcePreparer: any BrowserExtensionStoredResourcePreparing
    private let usesEphemeralWebKitStorage: Bool

    init(
        persistence: BrowserExtensionPersistenceController,
        permissions: BrowserExtensionPermissionController,
        contextObserver: BrowserExtensionContextObserver,
        commandController: BrowserExtensionCommandController,
        tabWindowCoordinator: BrowserExtensionTabWindowCoordinator,
        storedResourcePreparer:
            any BrowserExtensionStoredResourcePreparing,
        usesEphemeralWebKitStorage: Bool
    ) {
        _ = Self.customURLSchemeRegistration
        self.persistence = persistence
        self.permissions = permissions
        self.contextObserver = contextObserver
        self.commandController = commandController
        self.tabWindowCoordinator = tabWindowCoordinator
        self.storedResourcePreparer = storedResourcePreparer
        self.usesEphemeralWebKitStorage = usesEphemeralWebKitStorage
    }

    var nativeMessagingCapability: BrowserExtensionNativeMessagingCapability {
        tabWindowCoordinator.nativeMessagingCapability
    }

    func controller(for space: BrowserSpace) -> WKWebExtensionController {
        if let entry = controllerEntries[space.id] {
            precondition(
                entry.profileID == space.profile.id,
                "A Space cannot change browsing profiles after its extension controller is created."
            )
            return entry.controller
        }

        let configuration: WKWebExtensionController.Configuration
        let websiteDataStore: WKWebsiteDataStore
        if usesEphemeralWebKitStorage {
            configuration = .nonPersistent()
            websiteDataStore = .nonPersistent()
        } else {
            configuration = WKWebExtensionController.Configuration(
                identifier: space.id.rawValue
            )
            websiteDataStore = BrowserWebsiteDataStore.persistent(
                for: space.profile
            )
        }
        configuration.defaultWebsiteDataStore = websiteDataStore
        configuration.webViewConfiguration =
            BrowserPageConfiguration.make(
                for: space.profile,
                websiteDataStore: websiteDataStore
            )

        let controller = WKWebExtensionController(configuration: configuration)
        tabWindowCoordinator.register(
            controller: controller,
            spaceID: space.id
        )
        controllerEntries[space.id] = ControllerEntry(
            profileID: space.profile.id,
            controller: controller
        )
        return controller
    }

    func loadedContext(
        extensionID: String,
        in spaceID: SpaceID
    ) -> WKWebExtensionContext? {
        contextsBySpace[spaceID]?[extensionID]
    }

    func contexts(in spaceID: SpaceID) -> [String: WKWebExtensionContext] {
        contextsBySpace[spaceID] ?? [:]
    }

    func webViewConfiguration(
        for extensionURL: URL,
        in spaceID: SpaceID
    ) -> WKWebViewConfiguration? {
        contextsBySpace[spaceID]?.values.first(where: { context in
            extensionURL.scheme?.caseInsensitiveCompare(
                context.baseURL.scheme ?? ""
            ) == .orderedSame
                && extensionURL.host?.caseInsensitiveCompare(
                    context.baseURL.host ?? ""
                ) == .orderedSame
        })?.webViewConfiguration
    }

    func loadExtension(
        at resourceBaseURL: URL,
        extensionID: String,
        in space: BrowserSpace,
        unsupportedAPIs: Set<String>,
        permissionSnapshot: BrowserExtensionPermissionSnapshot,
        persistsRuntimeSummary: Bool,
        source: BrowserExtensionInstallationSource?
    ) async throws -> WKWebExtensionContext {
        if let existingContext = loadedContext(
            extensionID: extensionID,
            in: space.id
        ) {
            return existingContext
        }
        let webExtension = try await WKWebExtension(
            resourceBaseURL: resourceBaseURL
        )
        return try load(
            webExtension: webExtension,
            extensionID: extensionID,
            in: space,
            unsupportedAPIs: unsupportedAPIs,
            permissionSnapshot: permissionSnapshot,
            persistsRuntimeSummary: persistsRuntimeSummary,
            source: source
        )
    }

    func loadInstallation(
        _ installation: BrowserExtensionInstallation,
        in space: BrowserSpace
    ) async throws -> WKWebExtensionContext {
        if let existingContext = loadedContext(
            extensionID: installation.id,
            in: space.id
        ) {
            persistence.updateSummary(
                summary(for: existingContext, installation: installation),
                in: space.id
            )
            return existingContext
        }

        let context: WKWebExtensionContext
        switch installation.source {
        case nil, .unpackedPackage:
            context = try await loadStoredPackage(
                installation,
                in: space
            )
        case .safariWebExtension(let source):
            let resource =
                try await BrowserPlatformSafariWebExtensionLoader
                .load(source)
            context = try load(
                webExtension: resource.webExtension,
                extensionID: installation.id,
                in: space,
                unsupportedAPIs: Set(installation.unsupportedAPIs),
                permissionSnapshot: installation.permissionSnapshot,
                persistsRuntimeSummary: true,
                source: installation.source
            )
            runtimeResourceAccess[space.id, default: [:]][installation.id] =
                resource.access
        case .chromeWebStore, .mozillaAddons:
            context = try await loadStoredPackage(
                installation,
                in: space
            )
        }
        persistence.updateSummary(
            summary(for: context, installation: installation),
            in: space.id
        )
        return context
    }

    func load(
        webExtension: WKWebExtension,
        extensionID: String,
        in space: BrowserSpace,
        unsupportedAPIs: Set<String>,
        permissionSnapshot: BrowserExtensionPermissionSnapshot,
        persistsRuntimeSummary: Bool,
        source: BrowserExtensionInstallationSource?
    ) throws -> WKWebExtensionContext {
        let compatibility = BrowserExtensionCompatibilityPolicy.assess(
            extensionID: extensionID,
            requestedPermissions: webExtension.requestedPermissions
                .map(\.rawValue),
            source: BrowserExtensionCompatibilitySource(
                installationSource: source
            ),
            nativeMessagingCapability: nativeMessagingCapability
        )
        guard compatibility.canRun else {
            throw BrowserExtensionCompatibilityError(
                assessment: compatibility
            )
        }

        let context = WKWebExtensionContext(for: webExtension)
        // Private browsing is kept away from extensions by giving its page pool
        // no extension controller at all, not by this flag. What this flag has
        // to track is whether the web views this controller drives use a
        // non-persistent `WKWebsiteDataStore`, because WebKit treats those as
        // private data and will refuse content-script injection, messaging, and
        // tab access to a context without this access. An isolated launch or a
        // test runs every ordinary profile non-persistently, so extensions there
        // need the grant to work at all; production runs persistently and does
        // not.
        context.hasAccessToPrivateData = usesEphemeralWebKitStorage
        // Mirrors `BrowserPage`, which makes every ordinary web view
        // inspectable. An extension's background content and popups are the
        // parts a developer most needs Web Inspector for.
        context.isInspectable = true
        context.inspectionName = webExtension.displayName ?? extensionID
        let runtimeIdentity = BrowserExtensionRuntimeIdentifierPolicy.identity(
            extensionID: extensionID,
            source: source,
            spaceID: space.id
        )
        context.uniqueIdentifier = runtimeIdentity.uniqueIdentifier
        context.baseURL = runtimeIdentity.baseURL
        context.unsupportedAPIs = unsupportedAPIs
        let restoreError = permissions.apply(permissionSnapshot, to: context)
        let nativeMessagingIdentity: BrowserExtensionNativeMessagingIdentity?
        switch source {
        case .chromeWebStore(let chromeSource)
        where chromeSource.extensionID.rawValue == extensionID:
            nativeMessagingIdentity = .chromeWebStore(
                chromeSource.extensionID
            )
        case .mozillaAddons(let mozillaSource)
        where mozillaSource.extensionID.rawValue == extensionID:
            nativeMessagingIdentity = .mozillaAddons(
                mozillaSource.extensionID
            )
        default:
            nativeMessagingIdentity = nil
        }
        if let nativeMessagingIdentity {
            tabWindowCoordinator.registerVerifiedNativeMessagingIdentity(
                nativeMessagingIdentity,
                for: context
            )
        }
        do {
            try controller(for: space).load(context)
        } catch {
            tabWindowCoordinator.unregisterNativeMessagingIdentity(
                for: context
            )
            throw error
        }

        contextsBySpace[space.id, default: [:]][extensionID] = context
        commandController.captureDefaults(
            for: context,
            extensionID: extensionID,
            spaceID: space.id
        )
        commandController.applyStoredShortcuts(
            to: context,
            extensionID: extensionID,
            spaceID: space.id
        )
        contextObserver.observe(
            context,
            permissionsDidChange: { [weak self, weak context] in
                guard let self, let context else { return }
                self.persistPermissionState(
                    context: context,
                    extensionID: extensionID,
                    in: space.id
                )
            },
            runtimeSummaryDidChange: { [weak self, weak context] in
                guard let self, let context else { return }
                self.persistRuntimeSummary(
                    context: context,
                    extensionID: extensionID,
                    in: space.id
                )
            }
        )

        var runtimeSummary = summary(
            for: context,
            extensionID: extensionID,
            isEnabled: true
        )
        if let restoreError {
            runtimeSummary.errors = Array(
                Set(runtimeSummary.errors + [restoreError.localizedDescription])
            ).sorted()
        }
        persistence.updateSummary(runtimeSummary, in: space.id)
        if persistsRuntimeSummary {
            persistence.updateRuntimeSummary(
                runtimeSummary,
                extensionID: extensionID,
                in: space.id
            )
        }
        return context
    }

    func summary(
        for context: WKWebExtensionContext,
        extensionID: String,
        isEnabled: Bool
    ) -> BrowserExtensionSummary {
        persistence.summary(
            for: context,
            extensionID: extensionID,
            isEnabled: isEnabled,
            permissionSnapshot: permissions.snapshot(for: context)
        )
    }

    func summary(
        for context: WKWebExtensionContext,
        installation: BrowserExtensionInstallation
    ) -> BrowserExtensionSummary {
        persistence.summary(
            for: context,
            installation: installation,
            permissionSnapshot: permissions.snapshot(for: context)
        )
    }

    func persistPermissionState(
        extensionID: String,
        in spaceID: SpaceID
    ) {
        guard
            let context = loadedContext(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        persistPermissionState(
            context: context,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func releaseContext(
        extensionID: String,
        in spaceID: SpaceID
    ) {
        runtimeResourceAccess[spaceID]?.removeValue(forKey: extensionID)
        if runtimeResourceAccess[spaceID]?.isEmpty == true {
            runtimeResourceAccess.removeValue(forKey: spaceID)
        }
        commandController.releaseContext(
            extensionID: extensionID,
            in: spaceID
        )
        guard
            let context = contextsBySpace[spaceID]?.removeValue(
                forKey: extensionID
            )
        else {
            return
        }
        tabWindowCoordinator.unregisterNativeMessagingIdentity(for: context)
        contextObserver.stopObserving(context)
        if contextsBySpace[spaceID]?.isEmpty == true {
            contextsBySpace.removeValue(forKey: spaceID)
        }
    }

    func removeSpace(_ spaceID: SpaceID) {
        precondition(
            contextsBySpace[spaceID]?.isEmpty != false,
            "Extension contexts must be released before their Space controller."
        )
        contextsBySpace.removeValue(forKey: spaceID)
        controllerEntries.removeValue(forKey: spaceID)
        tabWindowCoordinator.unregister(spaceID: spaceID)
    }

    func retainRuntimeResourceAccess(
        _ access: AnyObject,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        runtimeResourceAccess[spaceID, default: [:]][extensionID] = access
    }

    private func loadStoredPackage(
        _ installation: BrowserExtensionInstallation,
        in space: BrowserSpace
    ) async throws -> WKWebExtensionContext {
        let storedResourceURL = try persistence.resourceURL(
            packageName: installation.packageName,
            in: space.id
        )
        let preparedResource = try storedResourcePreparer.prepare(
            resourceURL: storedResourceURL,
            installation: installation
        )
        let context = try await loadExtension(
            at: preparedResource.resourceURL,
            extensionID: installation.id,
            in: space,
            unsupportedAPIs: Set(installation.unsupportedAPIs),
            permissionSnapshot: installation.permissionSnapshot,
            persistsRuntimeSummary: true,
            source: installation.source
        )
        if let retainedAccess = preparedResource.retainedAccess {
            retainRuntimeResourceAccess(
                retainedAccess,
                extensionID: installation.id,
                in: space.id
            )
        }
        return context
    }

    private func persistPermissionState(
        context: WKWebExtensionContext,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        guard loadedContext(extensionID: extensionID, in: spaceID) === context
        else {
            return
        }
        permissions.persistPermissionState(
            context: context,
            extensionID: extensionID,
            in: spaceID
        )
    }

    private func persistRuntimeSummary(
        context: WKWebExtensionContext,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        guard loadedContext(extensionID: extensionID, in: spaceID) === context,
            let installation = persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        let runtimeSummary = summary(
            for: context,
            installation: installation
        )
        persistence.updateRuntimeSummary(
            runtimeSummary,
            extensionID: extensionID,
            in: spaceID
        )
        persistence.updateSummary(runtimeSummary, in: spaceID)
    }

}
