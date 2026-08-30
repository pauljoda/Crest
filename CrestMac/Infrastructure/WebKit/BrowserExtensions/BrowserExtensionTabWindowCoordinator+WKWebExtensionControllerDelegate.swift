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
    func requestActionPopup(
        _ action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        anchor: BrowserExtensionPopupAnchor?
    ) {
        let key = ObjectIdentifier(context)
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
                self.prepareActionPopupBackground(
                    for: context,
                    completion: completion
                )
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
        prepareActionPopupBackground(for: context) { _ in }
    }

    func isActionPopupLoading(
        for context: WKWebExtensionContext
    ) -> Bool {
        pendingActionPopupRequests[ObjectIdentifier(context)] != nil
    }

    private func prepareActionPopupBackground(
        for context: WKWebExtensionContext,
        completion: @escaping BrowserExtensionPopupBackgroundWarmUpObserver
    ) {
        let key = ObjectIdentifier(context)
        let now = popupBackgroundClock.now
        if let readyUntil = popupBackgroundReadyUntil[key],
            now < readyUntil
        {
            completion(.loaded)
            return
        }
        popupBackgroundReadyUntil.removeValue(forKey: key)
        if popupBackgroundWarmUpObservers[key] != nil {
            popupBackgroundWarmUpObservers[key]?.append(completion)
            return
        }
        popupBackgroundWarmUpObservers[key] = [completion]
        BrowserExtensionPopupBackgroundWarmUp(
            context: context,
            deadline: popupBackgroundWarmUpDeadline
        ).prepare { [weak self] outcome in
            guard let self else {
                completion(outcome)
                return
            }
            if case .loaded = outcome {
                self.popupBackgroundReadyUntil[key] =
                    self.popupBackgroundClock.now.advanced(
                        by: self.popupBackgroundWarmCacheDuration
                    )
            }
            let observers = self.popupBackgroundWarmUpObservers.removeValue(
                forKey: key
            ) ?? []
            for observer in observers {
                observer(outcome)
            }
        }
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
        // WebKit creates an extension action's popover outside Crest's SwiftUI
        // view hierarchy. Without an explicit appearance, that auxiliary
        // window can remain Aqua even while the browser and system are dark;
        // `prefers-color-scheme` then also reports the wrong value to every
        // extension popup. Carry the invoking window's resolved appearance
        // onto both WebKit-owned surfaces before presentation. Applying it to
        // the web view also updates a page that finished loading while WebKit
        // was constructing the popover.
        let appearance = presentationSource.view.effectiveAppearance
        popover.appearance = appearance
        action.popupWebView?.appearance = appearance
        if popover.isShown {
            action.closePopup()
            return true
        }
        popover.show(
            relativeTo: presentationSource.rect,
            of: presentationSource.view,
            preferredEdge: .maxY
        )
        // `NSPopover.show` creates its private window and can replace the
        // popover object's inherited appearance while doing so. Apply the
        // same resolved value to that concrete window once it exists.
        popover.contentViewController?.view.window?.appearance = appearance
        action.popupWebView?.appearance = appearance
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
