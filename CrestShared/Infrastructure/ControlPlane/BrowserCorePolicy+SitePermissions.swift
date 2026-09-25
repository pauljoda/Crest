import Foundation

/// Site-permission rules answered by the portable core: secure origins for
/// location and hosted notifications, the notification request action and the
/// blocked-popup notice transitions. Saved choices themselves live in the core
/// ledger behind `BrowserSitePermissionCenter`, and what a decision means
/// travels with the decision. Every answer fails closed.
extension BrowserCorePolicy {
    // MARK: - Types

    private struct OriginRequest: Encodable {
        let origin: SiteOrigin
    }

    private struct AllowedAnswer: Decodable {
        @BrowserCoreOptional var allowed: Bool?
    }

    private struct NotificationRequest: Encodable {
        let decision: SitePermissionDecision
        let hasUserActivation: Bool
    }

    private struct NotificationAnswer: Decodable {
        @BrowserCoreOptional var action: HostedNotificationRequestAction?
    }

    private struct PopupNoticeRequest: Encodable {
        struct State: Encodable {
            @BrowserCoreNullable var status: BlockedPopupStatus?
            @BrowserCoreNullable var origin: SiteOrigin?
            @BrowserCoreNullable var documentIdentifier: String?
            let indicationRevision: Int
        }

        let event: BlockedPopupEvent
        @BrowserCoreNullable var documentIdentifier: String?
        @BrowserCoreNullable var origin: SiteOrigin?
        let state: State
    }

    private struct PopupNoticeAnswer: Decodable {
        struct State: Decodable {
            @BrowserCoreOptional var status: BlockedPopupStatus?
            @BrowserCoreOptional var origin: SiteOrigin?
            @BrowserCoreOptional var documentIdentifier: String?
            let indicationRevision: Int
        }

        @BrowserCoreOptional var changed: Bool?
        let state: State
    }

    // MARK: - Actions - Site permissions

    /// Whether a site may use location at all. An unavailable core refuses.
    static func allowsGeolocation(for origin: SiteOrigin) -> Bool {
        evaluate(.geolocationOrigin, OriginRequest(origin: origin), answer: AllowedAnswer.self)?.allowed ?? false
    }

    /// Whether a site may post hosted web notifications at all. An unavailable core refuses.
    static func allowsHostedNotifications(for origin: SiteOrigin) -> Bool {
        evaluate(.notificationsOrigin, OriginRequest(origin: origin), answer: AllowedAnswer.self)?.allowed ?? false
    }

    /// What a notification permission request leads to. An unavailable core denies it.
    static func hostedNotificationPermissionRequestAction(
        for decision: SitePermissionDecision,
        hasUserActivation: Bool
    ) -> HostedNotificationRequestAction {
        let request = NotificationRequest(decision: decision, hasUserActivation: hasUserActivation)
        return evaluate(.notificationsPermissionRequest, request, answer: NotificationAnswer.self)?.action
            ?? .respondDenied
    }

    /// The page's popup state after one event, or nil when nothing changes or
    /// the core cannot answer; the caller then keeps its state and shows no
    /// new indication.
    static func blockedPopupState(
        after event: BlockedPopupEvent, from state: BrowserBlockedPopupPageState,
        documentIdentifier: String? = nil, origin: SiteOrigin? = nil
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
            notice = BrowserBlockedPopupNotice(origin: origin, status: status)
        }
        return BrowserBlockedPopupPageState(
            notice: notice, documentIdentifier: next.documentIdentifier,
            indicationRevision: next.indicationRevision)
    }
}
