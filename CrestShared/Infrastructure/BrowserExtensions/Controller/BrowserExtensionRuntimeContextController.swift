import Foundation
import WebKit
import os

/// Makes an extension background ready before another extension context sends
/// its first runtime message or opens its first Port.
///
/// Chromium retains an initial message while an extension background installs
/// its listeners. WebKit can instead report both persistent pages and workers
/// loaded before those listeners are ready, then lose the first message. A
/// deadline preserves startup for a genuinely broken background, while the
/// settlement window covers application bootstrap that continues after
/// WebKit's load callback.
@MainActor
final class BrowserExtensionBackgroundWarmUp {
    enum Outcome {
        case loaded
        case failed(any Error)
        case timedOut
    }

    typealias Load =
        @MainActor (@escaping @MainActor ((any Error)?) -> Void) -> Void

    nonisolated static let defaultDeadline = Duration.milliseconds(3000)
    nonisolated static let backgroundSettlementDelay =
        Duration.milliseconds(750)

    private let deadline: Duration
    private let settlementDelay: Duration
    private let load: Load
    private var hasFinished = false
    private var hasLoadReported = false

    init(
        deadline: Duration = BrowserExtensionBackgroundWarmUp.defaultDeadline,
        settlementDelay: Duration = .zero,
        load: @escaping Load
    ) {
        self.deadline = deadline
        self.settlementDelay = settlementDelay
        self.load = load
    }

    convenience init(
        context: WKWebExtensionContext?,
        deadline: Duration = BrowserExtensionBackgroundWarmUp.defaultDeadline
    ) {
        let settlementDelay =
            if context?.webExtension.hasBackgroundContent == true {
                Self.backgroundSettlementDelay
            } else {
                Duration.zero
            }
        self.init(
            deadline: deadline,
            settlementDelay: settlementDelay
        ) { loaded in
            guard let context else {
                loaded(nil)
                return
            }
            guard context.webExtension.hasBackgroundContent else {
                loaded(nil)
                return
            }
            context.loadBackgroundContent { error in
                MainActor.assumeIsolated { loaded(error) }
            }
        }
    }

    func prepare(
        _ body: @escaping @MainActor (Outcome) -> Void
    ) {
        load { [self] error in
            hasLoadReported = true
            if let error {
                finish(.failed(error), body)
                return
            }
            guard settlementDelay != .zero else {
                finish(.loaded, body)
                return
            }
            Task { @MainActor [self] in
                try? await Task.sleep(for: settlementDelay)
                finish(.loaded, body)
            }
        }
        Task { @MainActor [self] in
            try? await Task.sleep(for: deadline)
            guard !hasLoadReported else { return }
            finish(.timedOut, body)
        }
    }

    func prepare() async -> Outcome {
        await withCheckedContinuation { continuation in
            prepare { outcome in
                continuation.resume(returning: outcome)
            }
        }
    }

    private func finish(
        _ outcome: Outcome,
        _ body: @MainActor (Outcome) -> Void
    ) {
        guard !hasFinished else { return }
        hasFinished = true
        body(outcome)
    }
}

struct BrowserExtensionPageConfiguration {
    let baseURL: URL
    let context: WKWebExtensionContext
    let webViewConfiguration: WKWebViewConfiguration
    /// This page's identity to the emulated services, so a Crest-owned
    /// document can reach one without re-deriving the extension identifier
    /// WebKit no longer carries on the context.
    let clientID: BrowserExtensionServiceClientID
    /// The Space's union of authored `externally_connectable.matches`
    /// patterns, so a Crest-hosted extension document installs the same
    /// page-world `chrome.runtime` alias a browser tab gets. A site framed by
    /// a side panel is on the web, and Chrome exposes the namespace there.
    let externallyConnectableMatchPatterns: [String]

    init(
        baseURL: URL,
        context: WKWebExtensionContext,
        webViewConfiguration: WKWebViewConfiguration,
        clientID: BrowserExtensionServiceClientID,
        externallyConnectableMatchPatterns: [String] = []
    ) {
        self.baseURL = baseURL
        self.context = context
        self.webViewConfiguration = webViewConfiguration
        self.clientID = clientID
        self.externallyConnectableMatchPatterns =
            externallyConnectableMatchPatterns
    }
}

@MainActor
final class BrowserExtensionRuntimeContextController {
    private static let customURLSchemeRegistration: Void = {
        WKWebExtension.MatchPattern.registerCustomURLScheme(
            BrowserExtensionRuntimeIdentifierPolicy.urlScheme
        )
    }()

    private static let identityLog = Logger(
        subsystem: ProductIdentity.serviceNamespace,
        category: "extension-diagnostics"
    )

    private struct ControllerEntry {
        let profileID: UUID
        let controller: WKWebExtensionController
    }

    private var controllerEntries: [SpaceID: ControllerEntry] = [:]
    private var contextsBySpace: [SpaceID: [String: WKWebExtensionContext]] = [:]
    private var runtimeResourceAccess: [SpaceID: [String: AnyObject]] = [:]
    private var internalGrantedPermissionsBySpace: [SpaceID: [String: Set<String>]] = [:]

    private let persistence: BrowserExtensionPersistenceController
    private let permissions: BrowserExtensionPermissionController
    private let contextObserver: BrowserExtensionContextObserver
    private let commandController: BrowserExtensionCommandController
    private let tabWindowCoordinator: BrowserExtensionTabWindowCoordinator
    func requestSidebarOpenAtInstall(extensionID: String, in spaceID: SpaceID, didOpen: @escaping () -> Void) {
        tabWindowCoordinator.sidebarService?.requestOpenAtInstall(
            for: .scoped(extensionID: extensionID, spaceID: spaceID), didOpen: didOpen
        )
    }
    private let webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry
    private let storedResourcePreparer: any BrowserExtensionStoredResourcePreparing
    private let usesEphemeralWebKitStorage: Bool

    init(
        persistence: BrowserExtensionPersistenceController,
        permissions: BrowserExtensionPermissionController,
        contextObserver: BrowserExtensionContextObserver,
        commandController: BrowserExtensionCommandController,
        tabWindowCoordinator: BrowserExtensionTabWindowCoordinator,
        webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry,
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
        self.webpageMenuRegistry = webpageMenuRegistry
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

    /// Whether another Space already runs `extensionID` on the same
    /// `WKWebsiteDataStore` this Space's controller will use.
    ///
    /// `BrowserExtensionRuntimeIdentifierPolicy` hands a verified Chrome Web
    /// Store package its real `chrome-extension://<store id>/` origin, which
    /// is the same string in every Space. That is safe only while Spaces do
    /// not share WebKit storage, because a service-worker registration is
    /// keyed by origin *within* a data store and WebKit reuses a dormant
    /// registration instead of re-evaluating the worker. A Space's data store
    /// is `WKWebsiteDataStore(forIdentifier: profile.id)`, so two Spaces would
    /// have to hold the same `profile.id` — which `makeBlankSpace` never
    /// produces and `BrowserSession.repairRuntimeIntegrity` actively repairs.
    /// This answers the question from live state anyway rather than trusting
    /// that invariant.
    func sharesDataStoreWithAnotherLoadedContext(
        extensionID: String,
        in space: BrowserSpace
    ) -> Bool {
        controllerEntries.contains { spaceID, entry in
            spaceID != space.id
                && entry.profileID == space.profile.id
                && contextsBySpace[spaceID]?[extensionID] != nil
        }
    }

    func contexts(in spaceID: SpaceID) -> [String: WKWebExtensionContext] {
        contextsBySpace[spaceID] ?? [:]
    }

    /// Every `externally_connectable.matches` pattern authored by an extension
    /// loaded in `spaceID`, sorted so a page's script is stable across
    /// launches.
    func externallyConnectableMatchPatterns(in spaceID: SpaceID) -> [String] {
        Set(
            contexts(in: spaceID).values.flatMap {
                BrowserExtensionExternallyConnectablePolicy.matchPatterns(
                    in: $0.webExtension.manifest
                )
            }
        ).sorted()
    }

    func internallyGrantedPermissions(
        extensionID: String,
        in spaceID: SpaceID
    ) -> Set<String> {
        internalGrantedPermissionsBySpace[spaceID]?[extensionID] ?? []
    }

    func prepareBackgroundForInitialContentScriptTraffic(
        _ context: WKWebExtensionContext
    ) async -> BrowserExtensionBackgroundWarmUp.Outcome {
        await BrowserExtensionBackgroundWarmUp(context: context).prepare()
    }

    func extensionPageConfiguration(
        for extensionURL: URL,
        in spaceID: SpaceID
    ) -> BrowserExtensionPageConfiguration? {
        contextsBySpace[spaceID]?.first(where: { _, context in
            extensionURL.scheme?.caseInsensitiveCompare(
                context.baseURL.scheme ?? ""
            ) == .orderedSame
                && extensionURL.host?.caseInsensitiveCompare(
                    context.baseURL.host ?? ""
                ) == .orderedSame
        }).flatMap { extensionID, context in
            context.webViewConfiguration.map { configuration in
                // WebKit hands back a fresh copy, so clearing the mode here
                // never reaches the popups WebKit builds for itself.
                BrowserExtensionHostedPageConfigurationPolicy.clearExtensionContentSecurityPolicyMode(
                    on: configuration)
                return BrowserExtensionPageConfiguration(
                    baseURL: context.baseURL,
                    context: context,
                    webViewConfiguration: configuration,
                    clientID: .scoped(extensionID: extensionID, spaceID: spaceID),
                    externallyConnectableMatchPatterns:
                        externallyConnectableMatchPatterns(in: spaceID)
                )
            }
        }
    }

    /// The website data store a Space's extension web views were configured
    /// with, or `nil` before that Space has an extension controller.
    ///
    /// This is the store itself rather than a fresh
    /// `BrowserWebsiteDataStore.persistent(for:)` for the profile, so a caller
    /// that rewrites cookies cannot land them in a jar the extension's own
    /// frames never read.
    func websiteDataStore(in spaceID: SpaceID) -> WKWebsiteDataStore? {
        controllerEntries[spaceID]?.controller.configuration.defaultWebsiteDataStore
    }

    func loadExtension(
        at resourceBaseURL: URL,
        extensionID: String,
        in space: BrowserSpace,
        unsupportedAPIs: Set<String>,
        permissionSnapshot: BrowserExtensionPermissionSnapshot,
        persistsRuntimeSummary: Bool,
        source: BrowserExtensionInstallationSource?,
        internalGrantedPermissions: Set<String> = [],
        capabilityBrokerGrantedPermissions: Set<String> = [],
        allowsInternalCapabilityBroker: Bool = false
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
            source: source,
            internalGrantedPermissions: internalGrantedPermissions,
            capabilityBrokerGrantedPermissions:
                capabilityBrokerGrantedPermissions,
            allowsInternalCapabilityBroker: allowsInternalCapabilityBroker
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
                // The record's hide list is not re-fed: every hide Crest
                // applies comes from the matrix, which `load` recomputes.
                // Replaying the stored list would make an old matrix decision
                // permanent, and the summary written back here clears any
                // entry an earlier build persisted.
                unsupportedAPIs: [],
                permissionSnapshot: installation.permissionSnapshot,
                persistsRuntimeSummary: true,
                source: installation.source
            )
            runtimeResourceAccess[space.id, default: [:]][installation.id] =
                resource.access
        case .chromeWebStore, .mozillaAddons, .localPackage:
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
        source: BrowserExtensionInstallationSource?,
        internalGrantedPermissions: Set<String> = [],
        capabilityBrokerGrantedPermissions: Set<String> = [],
        allowsInternalCapabilityBroker: Bool = false
    ) throws -> WKWebExtensionContext {
        let authoredRequestedPermissions = BrowserExtensionManagedPermissionPolicy.requestedPermissions(
            native: webExtension.requestedPermissions.map(\.rawValue), manifest: webExtension.manifest,
            excluding: internalGrantedPermissions)
        let compatibility = BrowserExtensionCompatibilityPolicy.assess(
            extensionID: extensionID,
            requestedPermissions: authoredRequestedPermissions,
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
        let sharesDataStore = sharesDataStoreWithAnotherLoadedContext(
            extensionID: extensionID,
            in: space
        )
        if sharesDataStore {
            Self.identityLog.error(
                """
                Extension identity fell back to a per-Space origin: \
                \(extensionID, privacy: .public) already runs in another \
                Space on browsing profile \
                \(space.profile.id.uuidString, privacy: .public). \
                Chrome-origin behaviour that string-matches \
                chrome-extension://<store id> will not apply in this Space.
                """
            )
        }
        let runtimeIdentity = BrowserExtensionRuntimeIdentifierPolicy.identity(
            extensionID: extensionID,
            source: source,
            spaceID: space.id,
            sharesDataStoreWithAnotherContext: sharesDataStore
        )
        context.uniqueIdentifier = runtimeIdentity.uniqueIdentifier
        context.baseURL = runtimeIdentity.baseURL
        let platformUnsupportedAPIs: Set<String>
        switch source {
        case .some(.safariWebExtension):
            platformUnsupportedAPIs = []
        default:
            platformUnsupportedAPIs =
                BrowserExtensionAPICompatibilityMatrix
                .unsupportedWebKitAPIs(
                    requestedPermissions: authoredRequestedPermissions
                )
        }
        // The runtime still sees both sets. Only the persisted summary drops
        // the matrix half, so the routing table stays authoritative on every
        // launch instead of being ratcheted into the installation record.
        context.unsupportedAPIs = unsupportedAPIs.union(
            platformUnsupportedAPIs
        )
        let restoreError = permissions.apply(permissionSnapshot, to: context)
        for permissionName in internalGrantedPermissions {
            let permission =
                if permissionName == "nativeMessaging" {
                    WKWebExtension.Permission.nativeMessaging
                } else {
                    WKWebExtension.Permission(rawValue: permissionName)
                }
            context.setPermissionStatus(
                .grantedExplicitly,
                for: permission
            )
        }
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
        var authorizedPermissions = Set(
            permissionSnapshot.grantedPermissions.keys
        )
        authorizedPermissions.formUnion(
            capabilityBrokerGrantedPermissions
        )
        // Read from the loaded package, so a capability the broker runs
        // outside WebKit — today only a background worker's WebSocket — is
        // held to the same `connect-src` the extension's own pages are.
        let contentSecurityPolicy =
            BrowserExtensionWebSocketPolicy.extensionPagesPolicy(
                in: webExtension.manifest
            )
        let nativeMessagingAuthorization =
            BrowserExtensionNativeMessagingAuthorization(
                grantedPermissions: authorizedPermissions,
                clientID: .scoped(
                    extensionID: extensionID,
                    spaceID: space.id
                ),
                allowsInternalCapabilityBroker:
                    allowsInternalCapabilityBroker,
                contentSecurityPolicy: contentSecurityPolicy
            )
        if let nativeMessagingIdentity {
            tabWindowCoordinator.registerVerifiedNativeMessagingIdentity(
                nativeMessagingIdentity,
                authorization: nativeMessagingAuthorization,
                for: context
            )
        } else if allowsInternalCapabilityBroker {
            tabWindowCoordinator.registerCapabilityBrokerAuthorization(
                BrowserExtensionNativeMessagingAuthorization(
                    grantedPermissions: authorizedPermissions,
                    clientID: nativeMessagingAuthorization.clientID,
                    allowsInternalCapabilityBroker: true,
                    contentSecurityPolicy: contentSecurityPolicy
                ),
                for: context
            )
        }
        do {
            try controller(for: space).load(context)
        } catch {
            permissions.releaseContext(context)
            tabWindowCoordinator.unregisterNativeMessagingIdentity(
                for: context,
                in: space.id
            )
            webpageMenuRegistry.removeClient(
                .scoped(extensionID: extensionID, spaceID: space.id)
            )
            throw error
        }

        contextsBySpace[space.id, default: [:]][extensionID] = context
        // Tab groups are browser-wide, so every extension in the Space is a
        // potential reader whether or not it declared `tabGroups`. The
        // registration only tells the store which Space this client watches;
        // the broker still checks the grant on every call.
        tabWindowCoordinator.tabGroupService?.register(
            client: .scoped(extensionID: extensionID, spaceID: space.id),
            spaceID: space.id
        )
        let referenceEnvironment: BrowserExtensionReferenceEnvironment =
            if case .mozillaAddons = source { .firefox } else { .chromium }
        let sidebarDefaults =
            BrowserExtensionSidebarManifestPolicy.defaults(
                manifest: webExtension.manifest, referenceEnvironment: referenceEnvironment
            )
            ?? (Self.manifestDeclaresSidePanelPermission(webExtension.manifest, authored: authoredRequestedPermissions)
                ? BrowserExtensionSidebarDefaults(flavor: .sidePanel) : nil)
        if let sidebarDefaults {
            let sidebarClient = BrowserExtensionServiceClientID.scoped(extensionID: extensionID, spaceID: space.id)
            tabWindowCoordinator.sidebarService?.register(
                client: sidebarClient, spaceID: space.id,
                defaults: sidebarDefaults, displayName: webExtension.displayName ?? extensionID,
                baseURL: context.baseURL
            )
            tabWindowCoordinator.sidebarClientsByContext[ObjectIdentifier(context)] = sidebarClient
        }
        if authoredRequestedPermissions.contains("debugger") {
            tabWindowCoordinator.registerDebuggerClient(
                .init(
                    extensionID: extensionID, spaceID: space.id,
                    displayName: webExtension.displayName ?? extensionID, baseURL: context.baseURL),
                for: context
            )
        }
        internalGrantedPermissionsBySpace[space.id, default: [:]][extensionID] =
            internalGrantedPermissions
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
        isEnabled: Bool,
        source: BrowserExtensionInstallationSource? = nil
    ) -> BrowserExtensionSummary {
        let internalPermissions = internalGrantedPermissions(for: context)
        return persistence.summary(
            for: context,
            extensionID: extensionID,
            isEnabled: isEnabled,
            permissionSnapshot: permissions.snapshot(
                for: context,
                excluding: internalPermissions
            ),
            excluding: internalPermissions,
            // `load` decided on this axis which matrix hides to add; the
            // summary has to subtract on the same one.
            source: source
        )
    }

    func summary(
        for context: WKWebExtensionContext,
        installation: BrowserExtensionInstallation
    ) -> BrowserExtensionSummary {
        let internalPermissions = internalGrantedPermissions(for: context)
        return persistence.summary(
            for: context,
            installation: installation,
            permissionSnapshot: permissions.snapshot(
                for: context,
                excluding: internalPermissions
            ),
            excluding: internalPermissions
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
        webpageMenuRegistry.removeClient(
            .scoped(extensionID: extensionID, spaceID: spaceID)
        )
        internalGrantedPermissionsBySpace[spaceID]?[extensionID] = nil
        if internalGrantedPermissionsBySpace[spaceID]?.isEmpty == true {
            internalGrantedPermissionsBySpace.removeValue(forKey: spaceID)
        }
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
        tabWindowCoordinator.unregisterNativeMessagingIdentity(
            for: context,
            in: spaceID
        )
        permissions.releaseContext(context)
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
        internalGrantedPermissionsBySpace.removeValue(forKey: spaceID)
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
            request: BrowserExtensionStoredResourcePreparationRequest(
                extensionID: installation.id,
                source: installation.source,
                spaceID: installation.spaceID,
                requestedPermissions: installation.requestedPermissions,
                sharesDataStoreWithAnotherContext:
                    sharesDataStoreWithAnotherLoadedContext(
                        extensionID: installation.id,
                        in: space
                    )
            )
        )
        let context = try await loadExtension(
            at: preparedResource.resourceURL,
            extensionID: installation.id,
            in: space,
            // See `loadInstallation`: matrix hides are recomputed on every
            // load and never replayed from the record.
            unsupportedAPIs: [],
            permissionSnapshot: installation.permissionSnapshot,
            persistsRuntimeSummary: true,
            source: installation.source,
            internalGrantedPermissions:
                preparedResource.internalGrantedPermissions,
            capabilityBrokerGrantedPermissions:
                preparedResource.capabilityBrokerGrantedPermissions,
            allowsInternalCapabilityBroker:
                preparedResource.allowsInternalCapabilityBroker
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
            in: spaceID,
            excluding: internalGrantedPermissions(for: context)
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

    private func internalGrantedPermissions(
        for context: WKWebExtensionContext
    ) -> Set<String> {
        for (spaceID, contexts) in contextsBySpace {
            guard let entry = contexts.first(where: { $0.value === context })
            else { continue }
            return internalGrantedPermissionsBySpace[spaceID]?[entry.key]
                ?? []
        }
        return []
    }

    /// WebKit only reports the `sidePanel` permission while its own sidebar
    /// implementation is compiled in, so a package that declares the permission
    /// without a `side_panel` manifest key (Claude sets its panel path from the
    /// worker) would never register. The authored manifest is authoritative.
    private static func manifestDeclaresSidePanelPermission(
        _ manifest: [String: Any], authored: [String]
    ) -> Bool {
        authored.contains("sidePanel")
            || (manifest["permissions"] as? [String] ?? []).contains("sidePanel")
            || (manifest["optional_permissions"] as? [String] ?? []).contains("sidePanel")
    }

}
