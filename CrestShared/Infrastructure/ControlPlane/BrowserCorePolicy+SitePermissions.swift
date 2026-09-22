import Foundation

/// Site-permission rules answered by the portable core: secure origins for
/// location and hosted notifications, the notification request action, the
/// automatic-popup rule and the blocked-popup notice transitions. Saved
/// choices themselves live in the core ledger behind
/// `BrowserSitePermissionCenter`. Every answer fails closed.
extension BrowserCorePolicy {
    /// Whether a site may use location at all. An unavailable core refuses.
    static func allowsGeolocation(for origin: BrowserSiteOrigin) -> Bool {
        evaluate(["version": 1, "operation": "geolocation.origin",
            "origin": origin.coreValue])?["allowed"] as? Bool ?? false
    }

    /// Whether a site may post hosted web notifications at all. An unavailable core refuses.
    static func allowsHostedNotifications(for origin: BrowserSiteOrigin) -> Bool {
        evaluate(["version": 1, "operation": "notifications.origin",
            "origin": origin.coreValue])?["allowed"] as? Bool ?? false
    }

    /// What a notification permission request leads to. An unavailable core denies it.
    static func hostedNotificationPermissionRequestAction(for decision: BrowserSitePermissionDecision,
        hasUserActivation: Bool) -> BrowserHostedWebNotificationPermissionRequestAction {
        (evaluate(["version": 1, "operation": "notifications.permission_request", "decision": decision.rawValue,
            "hasUserActivation": hasUserActivation])?["action"] as? String)
            .flatMap(BrowserHostedWebNotificationPermissionRequestAction.init(rawValue:)) ?? .respondDenied
    }

    /// Whether the saved choice lets a site open windows without a gesture.
    /// An unavailable core keeps automatic popups blocked.
    static func allowsAutomaticPopups(decision: BrowserSitePermissionDecision) -> Bool {
        evaluate(["version": 1, "operation": "popups.automatic", "decision": decision.rawValue])?["allows"] as? Bool ?? false
    }

    enum BlockedPopupEvent: String {
        case blocked
        case permissionAllowed = "permission_allowed"
        case permissionBlockedAgain = "permission_blocked_again"
        case navigation
        case popupAllowed = "popup_allowed"
    }

    /// The page's popup state after one event, or nil when nothing changes or
    /// the core cannot answer; the caller then keeps its state and shows no
    /// new indication.
    static func blockedPopupState(after event: BlockedPopupEvent, from state: BrowserBlockedPopupPageState,
        documentIdentifier: String? = nil, origin: BrowserSiteOrigin? = nil) -> BrowserBlockedPopupPageState? {
        guard let response = evaluate([
            "version": 1, "operation": "popups.notice", "event": event.rawValue,
            "documentIdentifier": nonEmpty(documentIdentifier),
            "origin": origin.map { $0.coreValue } as Any? ?? NSNull(),
            "state": [
                "status": (state.notice?.status).map { $0 == .blocked ? "blocked" : "allowedAwaitingRetry" } as Any? ?? NSNull(),
                "origin": (state.notice?.origin).map { $0.coreValue } as Any? ?? NSNull(),
                "documentIdentifier": nonEmpty(state.documentIdentifier),
                "indicationRevision": state.indicationRevision,
            ] as [String: Any],
        ]), response["changed"] as? Bool == true, let next = response["state"] as? [String: Any],
            let revision = next["indicationRevision"] as? Int else { return nil }
        var notice: BrowserBlockedPopupNotice?
        if let status = next["status"] as? String, let values = next["origin"] as? [String: Any],
            let scheme = values["scheme"] as? String, let host = values["host"] as? String, let port = values["port"] as? Int {
            notice = BrowserBlockedPopupNotice(origin: BrowserSiteOrigin(scheme: scheme, host: host, port: port),
                status: status == "blocked" ? .blocked : .allowedAwaitingRetry)
        }
        return BrowserBlockedPopupPageState(notice: notice, documentIdentifier: next["documentIdentifier"] as? String,
            indicationRevision: revision)
    }
}

extension BrowserSiteOrigin {
    /// The origin as the core's permission operations spell it.
    var coreValue: [String: Any] { ["scheme": scheme, "host": host, "port": port] }
}
