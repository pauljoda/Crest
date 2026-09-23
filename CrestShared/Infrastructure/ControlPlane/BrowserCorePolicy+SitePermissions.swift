import Foundation

/// Site-permission rules answered by the portable core: secure origins for
/// location and hosted notifications, the notification request action, the
/// automatic-popup rule and the blocked-popup notice transitions. Saved
/// choices themselves live in the core ledger behind
/// `BrowserSitePermissionCenter`. Every answer fails closed.
extension BrowserCorePolicy {
    // MARK: - Types

    enum BlockedPopupEvent: String, Encodable {
        case blocked
        case permissionAllowed = "permission_allowed"
        case permissionBlockedAgain = "permission_blocked_again"
        case navigation
        case popupAllowed = "popup_allowed"
    }

    private struct OriginRequest: Encodable {
        let origin: BrowserSiteOrigin
    }

    private struct AllowedAnswer: Decodable {
        @BrowserCoreOptional var allowed: Bool?
    }

    private struct NotificationRequest: Encodable {
        let decision: BrowserSitePermissionDecision
        let hasUserActivation: Bool
    }

    private struct NotificationAnswer: Decodable {
        @BrowserCoreOptional var action: BrowserHostedWebNotificationPermissionRequestAction?
    }

    private struct DecisionRequest: Encodable {
        let decision: BrowserSitePermissionDecision
    }

    private struct AllowsAnswer: Decodable {
        @BrowserCoreOptional var allows: Bool?
    }

    private struct PopupNoticeRequest: Encodable {
        struct State: Encodable {
            @BrowserCoreNullable var status: BrowserBlockedPopupNotice.Status?
            @BrowserCoreNullable var origin: BrowserSiteOrigin?
            @BrowserCoreNullable var documentIdentifier: String?
            let indicationRevision: Int
        }

        let event: BlockedPopupEvent
        @BrowserCoreNullable var documentIdentifier: String?
        @BrowserCoreNullable var origin: BrowserSiteOrigin?
        let state: State
    }

    private struct PopupNoticeAnswer: Decodable {
        struct State: Decodable {
            /// An origin as the core spells it, normalized as any other origin.
            struct Origin: Decodable {
                let scheme: String
                let host: String
                let port: Int
            }

            @BrowserCoreOptional var status: BrowserBlockedPopupNotice.Status?
            @BrowserCoreOptional var origin: Origin?
            @BrowserCoreOptional var documentIdentifier: String?
            let indicationRevision: Int
        }

        @BrowserCoreOptional var changed: Bool?
        let state: State
    }

    // MARK: - Actions - Site permissions

    /// Whether a site may use location at all. An unavailable core refuses.
    static func allowsGeolocation(for origin: BrowserSiteOrigin) -> Bool {
        evaluate(.geolocationOrigin, OriginRequest(origin: origin), answer: AllowedAnswer.self)?.allowed ?? false
    }

    /// Whether a site may post hosted web notifications at all. An unavailable core refuses.
    static func allowsHostedNotifications(for origin: BrowserSiteOrigin) -> Bool {
        evaluate(.notificationsOrigin, OriginRequest(origin: origin), answer: AllowedAnswer.self)?.allowed ?? false
    }

    /// What a notification permission request leads to. An unavailable core denies it.
    static func hostedNotificationPermissionRequestAction(
        for decision: BrowserSitePermissionDecision,
        hasUserActivation: Bool
    ) -> BrowserHostedWebNotificationPermissionRequestAction {
        let request = NotificationRequest(decision: decision, hasUserActivation: hasUserActivation)
        return evaluate(.notificationsPermissionRequest, request, answer: NotificationAnswer.self)?.action
            ?? .respondDenied
    }

    /// Whether the saved choice lets a site open windows without a gesture.
    /// An unavailable core keeps automatic popups blocked.
    static func allowsAutomaticPopups(decision: BrowserSitePermissionDecision) -> Bool {
        evaluate(.popupsAutomatic, DecisionRequest(decision: decision), answer: AllowsAnswer.self)?.allows ?? false
    }

    /// The page's popup state after one event, or nil when nothing changes or
    /// the core cannot answer; the caller then keeps its state and shows no
    /// new indication.
    static func blockedPopupState(
        after event: BlockedPopupEvent, from state: BrowserBlockedPopupPageState,
        documentIdentifier: String? = nil, origin: BrowserSiteOrigin? = nil
    ) -> BrowserBlockedPopupPageState? {
        let request = PopupNoticeRequest(
            event: event, documentIdentifier: nonEmpty(documentIdentifier), origin: origin,
            state: PopupNoticeRequest.State(
                status: state.notice?.status, origin: state.notice?.origin,
                documentIdentifier: nonEmpty(state.documentIdentifier),
                indicationRevision: state.indicationRevision))
        guard let answer = evaluate(.popupsNotice, request, answer: PopupNoticeAnswer.self),
            answer.changed == true
        else { return nil }
        let next = answer.state
        var notice: BrowserBlockedPopupNotice?
        if let status = next.status, let origin = next.origin {
            notice = BrowserBlockedPopupNotice(
                origin: BrowserSiteOrigin(scheme: origin.scheme, host: origin.host, port: origin.port),
                status: status)
        }
        return BrowserBlockedPopupPageState(
            notice: notice, documentIdentifier: next.documentIdentifier,
            indicationRevision: next.indicationRevision)
    }
}
