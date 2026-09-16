import AppKit
import WebKit
import os

private let browserExtensionPopupLog = Logger(
    subsystem: ProductIdentity.serviceNamespace,
    category: "extension-popup"
)

extension BrowserExtensionTabWindowCoordinator:
    WKWebExtensionControllerDelegate
{
    /// A no-popup action still depends on a background listener. Wake it before
    /// dispatch, just as we do before a popup sends its first runtime message.
    func requestToolbarAction(for context: WKWebExtensionContext, tab: (any WKWebExtensionTab)?) {
        let key = ObjectIdentifier(context)
        guard pendingToolbarActionContexts.insert(key).inserted else { return }
        actionDidUpdate?()
        prepareActionPopupBackground(for: context) { [weak self, weak context] outcome in
            guard let self else { return }
            self.pendingToolbarActionContexts.remove(key)
            self.actionDidUpdate?()
            if case .failed(let error) = outcome, error is CancellationError { return }
            guard let context, let controller = context.webExtensionController,
                self.verifiedEntry(controller: controller, context: context) != nil
            else { return }
            // This is the original host click, deferred during wake-up. Start
            // its short authorization window when the worker can receive it.
            self.noteUserGesture(for: context)
            if let tab { context.userGesturePerformed(in: tab) }
            browserExtensionPopupLog.notice(
                "dispatching toolbar action after background preparation for \(context.uniqueIdentifier, privacy: .public)"
            )
            context.performAction(for: tab)
        }
    }

    func requestActionPopup(
        _ action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        anchor: BrowserExtensionPopupAnchor?
    ) {
        let key = ObjectIdentifier(context)
        if popupToggle.consumeDismissal(for: key) { return }
        if popupToggle.closeIfShown(for: key) { return }
        guard pendingActionPopupRequests[key] == nil else { return }
        let request = BrowserExtensionActionPopupRequest(
            id: UUID(),
            anchor: anchor
        )
        pendingActionPopupRequests[key] = request
        actionDidUpdate?()
        BrowserExtensionPopupActionRequest(
            prepareBackground: { [weak self, weak context] completion in
                guard let self, let context else {
                    completion(.timedOut)
                    return
                }
                self.popupToggle.afterClosing(key) { [weak self, weak context] in
                    guard let self, let context else {
                        completion(.timedOut)
                        return
                    }
                    self.prepareActionPopupBackground(for: context, completion: completion)
                }
            },
            performAction: { [weak self] in
                guard let self,
                    self.pendingActionPopupRequests[key]?.id == request.id
                else {
                    browserExtensionPopupLog.error(
                        "discarded stale action popup request"
                    )
                    return
                }
                BrowserExtensionBackgroundActivityLease(
                    context: context,
                    isActive: { [weak self] in
                        self?.pendingActionPopupRequests[key]?.id
                            == request.id
                    }
                ).start()
                context.performAction(for: action.associatedTab)
            },
            presentationDeadline: popupPresentationDeadline,
            isPresentationSettled: { [weak self, weak action] in
                guard let self,
                    self.pendingActionPopupRequests[key]?.id == request.id
                else {
                    return true
                }
                guard
                    let action,
                    self.isActionPopupPresented(action)
                else {
                    return false
                }
                self.takeActionPopupRequest(for: key)
                return true
            },
            presentFallback: { [weak self] in
                guard let self,
                    self.pendingActionPopupRequests[key]?.id == request.id,
                    let pendingRequest = self.takeActionPopupRequest(
                        for: key
                    )
                else {
                    return
                }
                browserExtensionPopupLog.error(
                    "WebKit missed action popup presentation; using bounded fallback"
                )
                if !self.presentActionPopup(
                    action,
                    anchor: pendingRequest.anchor
                ) {
                    browserExtensionPopupLog.error(
                        "bounded action popup fallback could not find an anchor"
                    )
                }
            }
        ).start {
            [weak self, weak context] outcome in
            guard let self, let context,
                self.pendingActionPopupRequests[key]?.id == request.id
            else {
                return
            }
            switch outcome {
            case .loaded:
                browserExtensionPopupLog.notice(
                    """
                    background ready for \
                    \(context.uniqueIdentifier, privacy: .public)
                    """
                )
            case .failed(let error):
                let cocoaError = error as NSError
                browserExtensionPopupLog.error(
                    """
                    background failed for \
                    \(context.uniqueIdentifier, privacy: .public): \
                    \(cocoaError.domain, privacy: .public)#\(cocoaError.code, privacy: .public) \
                    \(cocoaError.localizedDescription, privacy: .public)
                    """
                )
            case .timedOut:
                browserExtensionPopupLog.error(
                    """
                    background timed out for \
                    \(context.uniqueIdentifier, privacy: .public)
                    """
                )
            }
        }
    }

    func prepareActionPopup(
        _ action: WKWebExtension.Action,
        for context: WKWebExtensionContext
    ) {
        guard action.presentsPopup else { return }
        prepareActionPopupBackground(for: context, allowsRecovery: false) { _ in }
    }

    func isActionPopupLoading(
        for context: WKWebExtensionContext
    ) -> Bool {
        pendingActionPopupRequests[ObjectIdentifier(context)] != nil
            || pendingToolbarActionContexts.contains(ObjectIdentifier(context))
    }

    func prepareBackgroundForInitialContentScriptTraffic(
        _ context: WKWebExtensionContext
    ) async -> BrowserExtensionBackgroundWarmUp.Outcome {
        await withCheckedContinuation { continuation in
            prepareActionPopupBackground(for: context, allowsRecovery: false) { outcome in
                continuation.resume(returning: outcome)
            }
        }
    }

    private func prepareActionPopupBackground(
        for context: WKWebExtensionContext,
        allowsRecovery: Bool = true,
        completion: @escaping BrowserExtensionPopupBackgroundWarmUpObserver
    ) {
        let key = ObjectIdentifier(context)
        if allowsRecovery { popupBackgroundRecoveryRequests.insert(key) }
        let now = popupBackgroundClock.now
        let endpoint = verifiedNativeMessagingAuthorizations[key]?.clientID.flatMap {
            BrowserExtensionBackgroundHealth.shared.endpointID(for: $0)
        }
        let usesHealth = backgroundHealthContexts.contains(key) && nativeMessagingHandler != nil
        // A live endpoint that already completed bootstrap stays prepared as
        // long as that exact background generation survives. Every action still
        // challenges it; a replacement must complete the normal warm-up again.
        let recentlyPrepared =
            usesHealth
            ? endpoint != nil && popupBackgroundReadyEndpoints[key] == endpoint
            : popupBackgroundReadyUntil[key].map { now < $0 } == true
        if popupBackgroundPreparations[key] != nil {
            popupBackgroundPreparations[key]?.observers.append(completion)
            return
        }
        let preparation = BrowserExtensionPopupBackgroundPreparation(observers: [completion])
        popupBackgroundPreparations[key] = preparation
        let generation = preparation.generation
        let finish: BrowserExtensionPopupBackgroundWarmUpObserver = { [weak self] outcome in
            guard let self else {
                completion(outcome)
                return
            }
            Task { @MainActor in
                guard self.popupBackgroundPreparations[key]?.generation == generation else { return }
                let verifiedOutcome = await self.verifyActionBackground(
                    context, outcome: outcome, generation: generation)
                guard self.popupBackgroundPreparations[key]?.generation == generation else { return }
                if case .loaded = verifiedOutcome {
                    self.popupBackgroundReadyUntil[key] =
                        self.popupBackgroundClock.now.advanced(by: self.popupBackgroundWarmCacheDuration)
                }
                let observers = self.popupBackgroundPreparations.removeValue(forKey: key)?.observers ?? []
                self.popupBackgroundRecoveryRequests.remove(key)
                for observer in observers { observer(verifiedOutcome) }
            }
        }
        if recentlyPrepared {
            finish(.loaded)
        } else {
            BrowserExtensionPopupBackgroundWarmUp(context: context, deadline: popupBackgroundWarmUpDeadline)
                .prepare(finish)
        }
    }

    private func verifyActionBackground(
        _ context: WKWebExtensionContext, outcome: BrowserExtensionBackgroundWarmUp.Outcome, generation: UUID
    ) async -> BrowserExtensionBackgroundWarmUp.Outcome {
        let key = ObjectIdentifier(context)
        guard case .loaded = outcome else { return outcome }
        guard let controller = context.webExtensionController,
            verifiedEntry(controller: controller, context: context) != nil
        else { return .failed(CancellationError()) }
        guard backgroundHealthContexts.contains(key), nativeMessagingHandler != nil,
            let client = verifiedNativeMessagingAuthorizations[key]?.clientID
        else { return outcome }
        func isCurrentPreparation() -> Bool {
            popupBackgroundPreparations[key]?.generation == generation
                && context.webExtensionController === controller
                && verifiedEntry(controller: controller, context: context) != nil
                && verifiedNativeMessagingAuthorizations[key]?.clientID == client
        }
        let health = BrowserExtensionBackgroundHealth.shared
        let endpoint = health.endpointID(for: client)
        let responds = await health.responds(client: client)
        guard isCurrentPreparation() else { return .failed(CancellationError()) }
        if responds, let endpoint, health.endpointID(for: client) == endpoint {
            popupBackgroundReadyEndpoints[key] = endpoint
            return .loaded
        }
        popupBackgroundReadyEndpoints[key] = nil
        // Hover can prepare a background, but only an actual action may reload
        // it. A click joining a pending hover request upgrades that request.
        guard popupBackgroundRecoveryRequests.contains(key), backgroundHealthContexts.contains(key),
            context.webExtensionController === controller,
            verifiedEntry(controller: controller, context: context) != nil,
            controller.configuration.isPersistent
        else { return .timedOut }
        browserExtensionPopupLog.error(
            "background did not answer; restarting background for \(context.uniqueIdentifier, privacy: .public)")
        let recovered = await BrowserExtensionBackgroundRestart.prepare(context)
        guard isCurrentPreparation() else { return .failed(CancellationError()) }
        guard case .loaded = recovered else { return recovered }
        let recoveredEndpoint = health.endpointID(for: client)
        let recoveredResponds = await health.responds(client: client)
        guard isCurrentPreparation() else { return .failed(CancellationError()) }
        guard recoveredResponds, let recoveredEndpoint,
            health.endpointID(for: client) == recoveredEndpoint
        else {
            browserExtensionPopupLog.error(
                "background did not answer after recovery for \(context.uniqueIdentifier, privacy: .public)")
            return .timedOut
        }
        popupBackgroundReadyEndpoints[key] = recoveredEndpoint
        browserExtensionPopupLog.notice(
            "background recovered for \(context.uniqueIdentifier, privacy: .public)")
        return .loaded
    }

    @discardableResult
    private func takeActionPopupRequest(
        for key: ObjectIdentifier
    ) -> BrowserExtensionActionPopupRequest? {
        guard let request = pendingActionPopupRequests.removeValue(forKey: key)
        else {
            return nil
        }
        actionDidUpdate?()
        return request
    }

    @discardableResult
    func presentActionPopup(
        _ action: WKWebExtension.Action,
        anchor: BrowserExtensionPopupAnchor?
    ) -> Bool {
        guard
            action.presentsPopup,
            let presentationSource = anchor?.presentationSource(
                fallbackWindow: NSApp.keyWindow
            ),
            let popover = action.popupPopover
        else {
            return false
        }
        // WebKit chooses the popup appearance from the document's supported
        // color schemes. Forcing the browser's dark appearance onto its web
        // view gives light-only extensions white text on white backgrounds.
        if popover.isShown {
            action.closePopup()
            return true
        }
        if let context = action.webExtensionContext {
            let key = ObjectIdentifier(context)
            popupToggle.observe(popover, action: action, key: key, anchor: anchor) { [weak self] in
                self?.actionDidUpdate?()
            }
        }
        popover.show(
            relativeTo: presentationSource.rect,
            of: presentationSource.view,
            preferredEdge: .maxY
        )
        return true
    }

    private func isActionPopupPresented(
        _ action: WKWebExtension.Action
    ) -> Bool {
        action.popupPopover?.isShown == true
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            verifiedEntry(
                controller: controller,
                context: context
            ) != nil
        else {
            completionHandler(adapterError(.windowUnavailable))
            return
        }
        let requestedPopup = takeActionPopupRequest(
            for: ObjectIdentifier(context)
        )
        if requestedPopup == nil,
            isActionPopupPresented(action)
        {
            // A bounded fallback already presented this action after WebKit
            // missed its first delegate handoff. A late callback acknowledges
            // that presentation instead of toggling the popup closed again.
            completionHandler(nil)
            return
        }
        guard
            presentActionPopup(
                action,
                anchor: requestedPopup?.anchor
                    ?? BrowserExtensionPopupAnchor(
                        screenPoint: NSEvent.mouseLocation,
                        sourceWindow: NSApp.keyWindow
                    )
            )
        else {
            completionHandler(adapterError(.windowUnavailable))
            return
        }
        completionHandler(nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        let declared = context.webExtension.requestedPermissions.union(context.webExtension.optionalPermissions)
        requestAccess(
            permissions, declared: { declared.contains($0) },
            status: { context.permissionStatus(for: $0, in: tab) },
            label: { "permission:" + $0.rawValue }, display: { $0.rawValue },
            save: { context.setPermissionStatus($1, for: $0) },
            controller: controller, tab: tab, context: context, completion: completionHandler)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let declared = context.webExtension.allRequestedMatchPatterns.union(
            context.webExtension.optionalPermissionMatchPatterns)
        requestAccess(
            urls, declared: { url in declared.contains { $0.matches(url) } },
            status: { context.permissionStatus(for: $0, in: tab) },
            label: { "url:" + $0.absoluteString },
            display: { url in
                // Show the origin, never a conversation path, query, or fragment.
                var origin = URLComponents()
                origin.scheme = url.scheme
                origin.host = url.host
                origin.port = url.port
                return origin.string ?? "Website"
            }, save: { context.setPermissionStatus($1, for: $0) },
            controller: controller, tab: tab, context: context, completion: completionHandler)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let declared = context.webExtension.allRequestedMatchPatterns.union(
            context.webExtension.optionalPermissionMatchPatterns)
        requestAccess(
            patterns, declared: { pattern in declared.contains { $0.matches(pattern) } },
            status: { context.permissionStatus(for: $0, in: tab) },
            label: { "pattern:" + $0.string }, display: { $0.string },
            save: { context.setPermissionStatus($1, for: $0) },
            controller: controller, tab: tab, context: context, completion: completionHandler)
    }

    private func requestAccess<Value: Hashable>(
        _ values: Set<Value>, declared: (Value) -> Bool,
        status: @escaping (Value) -> WKWebExtensionContext.PermissionStatus,
        label: (Value) -> String, display: (Value) -> String,
        save: @escaping (Value, WKWebExtensionContext.PermissionStatus) -> Void,
        controller: WKWebExtensionController, tab: (any WKWebExtensionTab)?, context: WKWebExtensionContext,
        completion: @escaping (Set<Value>, Date?) -> Void
    ) {
        guard let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: context),
            validates(tab, for: spaceID)
        else {
            completion([], nil)
            return
        }
        if let adapter = tab as? BrowserExtensionTabAdapter {
            guard self.tab(for: adapter.tabID, in: spaceID) === adapter else {
                completion([], nil)
                return
            }
        }
        let eligible = values.filter { declared($0) && !Self.isDenied(status($0)) }
        let granted = eligible.filter { Self.isGranted(status($0)) }
        let requested = eligible.subtracting(granted)
        guard !requested.isEmpty else {
            completion(granted, nil)
            return
        }
        let adapter = tab as? BrowserExtensionTabAdapter
        let initialURL = adapter.flatMap { state(for: $0.tabID, in: spaceID, context: context)?.url }
        let initialStatuses = Dictionary(uniqueKeysWithValues: requested.map { ($0, status($0)) })
        let selectedID = currentState?.space(spaceID)?.selectedTabID
        let window =
            adapter?.webView(for: context)?.window
            ?? selectedID.flatMap { pageProvider(for: $0, in: spaceID)?.extensionWebView(for: $0, in: spaceID)?.window }
            ?? currentState?.space(spaceID)?.tabs.lazy.compactMap {
                self.pageProvider(for: $0.id, in: spaceID)?.extensionWebView(for: $0.id, in: spaceID)?.window
            }.first
        guard let window, window.isVisible, currentState?.selectedSpaceID == spaceID else {
            completion(granted, nil)
            return
        }
        let key = BrowserExtensionPermissionPromptController.Key(
            context: ObjectIdentifier(context), tab: adapter?.tabID, access: requested.map(label).sorted())
        let displayedAccess = Set(requested.map(display)).sorted().joined(separator: "\n")
        permissionPrompts.request(
            key: key,
            isValid: { [weak self, weak context, weak window] in
                guard let self, let context, let window, window.isVisible,
                    self.owns(context: context, spaceID: spaceID),
                    self.currentState?.selectedSpaceID == spaceID,
                    requested.allSatisfy({ status($0) == initialStatuses[$0] })
                else { return false }
                guard let adapter else { return true }
                guard let current = self.state(for: adapter.tabID, in: spaceID, context: context),
                    current.url == initialURL
                else { return false }
                return self.tab(for: adapter.tabID, in: spaceID) === adapter
            },
            completion: { decision in
                switch decision {
                case .allow:
                    let allowed = requested.filter { !Self.isDenied(status($0)) }
                    // WebKit commits grants after combining permission and host
                    // delegates. Saving here would approve half of a rejected
                    // permissions.request() operation.
                    completion(granted.union(allowed), nil)
                case .deny:
                    for value in requested { save(value, .deniedExplicitly) }
                    completion(granted, nil)
                case .cancel:
                    completion(granted.filter { Self.isGranted(status($0)) }, nil)
                }
            },
            present: { [weak self, weak context, weak window] finish in
                guard let self, let context, let window, window.attachedSheet == nil else {
                    finish(.cancel)
                    return {}
                }
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "Allow \(context.webExtension.displayName ?? "Extension")?"
                let spaceName = self.browser?.session.space(id: spaceID)?.name ?? "this Space"
                alert.informativeText =
                    "This extension is requesting access in \(spaceName):\n\n"
                    + displayedAccess
                    + "\n\nYour choice is saved for this extension in this Space. Change it later in Extensions settings."
                alert.addButton(withTitle: "Allow")
                alert.addButton(withTitle: "Don’t Allow").keyEquivalent = "\u{1b}"
                alert.beginSheetModal(for: window) { response in
                    finish(response == .alertFirstButtonReturn ? .allow : .deny)
                }
                return {
                    if alert.window.sheetParent != nil {
                        window.endSheet(alert.window, returnCode: .abort)
                    }
                    alert.window.orderOut(nil)
                }
            })
    }

    private static func isDenied(_ status: WKWebExtensionContext.PermissionStatus) -> Bool {
        status == .deniedExplicitly || status == .deniedImplicitly
    }

    private static func isGranted(_ status: WKWebExtensionContext.PermissionStatus) -> Bool {
        status == .grantedExplicitly || status == .grantedImplicitly
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            verifiedEntry(
                controller: controller,
                context: context
            ) != nil
        else {
            completionHandler(adapterError(.crossSpaceRequest))
            return
        }
        presentOptionsPage(for: context, completionHandler: completionHandler)
    }

}
