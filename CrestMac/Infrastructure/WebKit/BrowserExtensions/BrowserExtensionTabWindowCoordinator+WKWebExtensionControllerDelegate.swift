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
        prepareActionPopupBackground(for: context) { [weak self, weak context] _ in
            guard let self else { return }
            self.pendingToolbarActionContexts.remove(key)
            self.actionDidUpdate?()
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

    private func prepareActionPopupBackground(
        for context: WKWebExtensionContext,
        allowsRecovery: Bool = true,
        completion: @escaping BrowserExtensionPopupBackgroundWarmUpObserver
    ) {
        let key = ObjectIdentifier(context)
        if allowsRecovery { popupBackgroundRecoveryRequests.insert(key) }
        let now = popupBackgroundClock.now
        let recentlyPrepared = popupBackgroundReadyUntil[key].map { now < $0 } == true
        if !recentlyPrepared { popupBackgroundReadyUntil.removeValue(forKey: key) }
        if popupBackgroundWarmUpObservers[key] != nil {
            popupBackgroundWarmUpObservers[key]?.append(completion)
            return
        }
        popupBackgroundWarmUpObservers[key] = [completion]
        let finish: BrowserExtensionPopupBackgroundWarmUpObserver = { [weak self] outcome in
            guard let self else {
                completion(outcome)
                return
            }
            Task { @MainActor in
                let verifiedOutcome = await self.verifyActionBackground(context, outcome: outcome)
                if case .loaded = verifiedOutcome {
                    self.popupBackgroundReadyUntil[key] =
                        self.popupBackgroundClock.now.advanced(by: self.popupBackgroundWarmCacheDuration)
                }
                let observers = self.popupBackgroundWarmUpObservers.removeValue(forKey: key) ?? []
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
        _ context: WKWebExtensionContext, outcome: BrowserExtensionBackgroundWarmUp.Outcome
    ) async -> BrowserExtensionBackgroundWarmUp.Outcome {
        let key = ObjectIdentifier(context)
        guard case .loaded = outcome, backgroundHealthContexts.contains(key), nativeMessagingHandler != nil,
            let client = verifiedNativeMessagingAuthorizations[key]?.clientID,
            let controller = context.webExtensionController,
            verifiedEntry(controller: controller, context: context) != nil
        else { return outcome }
        if await BrowserExtensionBackgroundHealth.shared.responds(client: client) { return .loaded }
        // Hover can prepare a background, but only an actual action may reload
        // it. A click joining a pending hover request upgrades that request.
        guard popupBackgroundRecoveryRequests.contains(key), backgroundHealthContexts.contains(key),
            context.webExtensionController === controller,
            verifiedEntry(controller: controller, context: context) != nil,
            controller.configuration.isPersistent
        else { return .timedOut }
        browserExtensionPopupLog.error(
            "background did not answer; reloading context for \(context.uniqueIdentifier, privacy: .public)")
        do {
            // Preserve the context identity, grants and persistent storage. A
            // full context reload closes WebKit's lingering background page;
            // loadBackgroundContent alone cannot restart its stopped worker.
            try controller.unload(context)
            try controller.load(context)
        } catch { return .failed(error) }
        let recovered = await BrowserExtensionBackgroundWarmUp(context: context).prepare()
        guard case .loaded = recovered else { return recovered }
        guard await BrowserExtensionBackgroundHealth.shared.responds(client: client) else {
            browserExtensionPopupLog.error(
                "background did not answer after recovery for \(context.uniqueIdentifier, privacy: .public)")
            return .timedOut
        }
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
                self?.popupBackgroundReadyUntil[key] = nil
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
        in tab: (any WKWebExtensionTab)?,
        for context: WKWebExtensionContext,
        completionHandler:
            @escaping (
                Set<WKWebExtension.Permission>, Date?
            ) -> Void
    ) {
        guard
            verifiedEntry(
                controller: controller,
                context: context
            ) != nil
        else {
            completionHandler([], nil)
            return
        }
        presentPermissionPrompt(
            extensionName: context.webExtension.displayName ?? "Extension",
            accessKind: "permissions",
            values: permissions.map(\.rawValue).sorted()
        ) { allowed in
            completionHandler(allowed ? permissions : [], nil)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        guard
            verifiedEntry(
                controller: controller,
                context: context
            ) != nil
        else {
            completionHandler([], nil)
            return
        }
        presentPermissionPrompt(
            extensionName: context.webExtension.displayName ?? "Extension",
            accessKind: "websites",
            values: urls.map(\.absoluteString).sorted()
        ) { allowed in
            completionHandler(allowed ? urls : [], nil)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns patterns:
            Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for context: WKWebExtensionContext,
        completionHandler:
            @escaping (
                Set<WKWebExtension.MatchPattern>, Date?
            ) -> Void
    ) {
        guard
            verifiedEntry(
                controller: controller,
                context: context
            ) != nil
        else {
            completionHandler([], nil)
            return
        }
        presentPermissionPrompt(
            extensionName: context.webExtension.displayName ?? "Extension",
            accessKind: "website patterns",
            values: patterns.map(\.string).sorted()
        ) { allowed in
            completionHandler(allowed ? patterns : [], nil)
        }
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

    private func presentPermissionPrompt(
        extensionName: String,
        accessKind: String,
        values: [String],
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow \(extensionName)?"
        alert.informativeText = "This extension is requesting \(accessKind):\n\n\(values.joined(separator: "\n"))"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                completion(response == .alertFirstButtonReturn)
            }
        } else {
            completion(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}
