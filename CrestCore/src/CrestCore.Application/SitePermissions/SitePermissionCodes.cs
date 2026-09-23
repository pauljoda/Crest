using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for site permissions, shared by the permission ledger and
/// the origin policy operations. They match the native projection's case
/// names, and origins use the native record's `scheme`, `host` and `port`.
internal static class SitePermissionCodes {
    #region Variables

    public const string Scheme = "scheme";
    public const string Host = "host";
    public const string Port = "port";
    private const string OriginField = "origin";

    #endregion

    #region Actions - Encoding

    public static string Permission(SitePermission permission) => permission switch {
        SitePermission.AutomaticDownloads => "automaticDownloads",
        SitePermission.Camera => "camera",
        SitePermission.CameraAndMicrophone => "cameraAndMicrophone",
        SitePermission.ExternalApplications => "externalApplications",
        SitePermission.Location => "location",
        SitePermission.Microphone => "microphone",
        SitePermission.Notifications => "notifications",
        _ => "popups"
    };

    public static string Decision(SitePermissionDecision decision) => decision switch {
        SitePermissionDecision.GrantForSession => "grantForSession",
        SitePermissionDecision.DenyForSession => "denyForSession",
        SitePermissionDecision.GrantPersistently => "grantPersistently",
        SitePermissionDecision.DenyPersistently => "denyPersistently",
        _ => "ask"
    };

    public static JsonObject Origin(SiteOrigin origin) => new() {
        [Scheme] = origin.Scheme,
        [Host] = origin.Host,
        [Port] = origin.Port
    };

    public static string NotificationAction(HostedNotificationRequestAction action) => action switch {
        HostedNotificationRequestAction.RespondDefault => "respondDefault",
        HostedNotificationRequestAction.ResolveSystemAuthorization => "resolveSystemAuthorization",
        HostedNotificationRequestAction.PromptForSitePermission => "promptForSitePermission",
        _ => "respondDenied"
    };

    public static string? PopupStatus(BlockedPopupStatus? status) => status switch {
        BlockedPopupStatus.Blocked => "blocked",
        BlockedPopupStatus.AllowedAwaitingRetry => "allowedAwaitingRetry",
        _ => null
    };

    public static JsonObject PopupState(BlockedPopupPageState state) => new() {
        ["status"] = PopupStatus(state.Status),
        [OriginField] = state.Origin is { } origin ? Origin(origin) : null,
        ["documentIdentifier"] = state.DocumentIdentifier,
        ["indicationRevision"] = state.IndicationRevision
    };

    public static JsonObject OriginAnswer(bool allowed) => new() { ["allowed"] = allowed };

    public static JsonObject NotificationAnswer(HostedNotificationRequestAction action) =>
        new() { ["action"] = NotificationAction(action) };

    public static JsonObject PopupsAnswer(bool allows) => new() { ["allows"] = allows };

    /// The page's popup notice after an event; `changed` is false when the
    /// event left the state as it was.
    public static JsonObject NoticeAnswer(BlockedPopupPageState? next, BlockedPopupPageState current) => new() {
        ["changed"] = next is not null,
        ["state"] = PopupState(next ?? current)
    };

    #endregion

    #region Actions - Decoding

    public static SitePermission? ParsePermission(string? value) => value switch {
        "automaticDownloads" => SitePermission.AutomaticDownloads,
        "camera" => SitePermission.Camera,
        "cameraAndMicrophone" => SitePermission.CameraAndMicrophone,
        "externalApplications" => SitePermission.ExternalApplications,
        "location" => SitePermission.Location,
        "microphone" => SitePermission.Microphone,
        "notifications" => SitePermission.Notifications,
        "popups" => SitePermission.Popups,
        _ => null
    };

    public static SitePermission Permission(JsonElement request, string field) =>
        ParsePermission(Protocol.Text(request, field, 64)) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidSitePermission);

    public static SitePermissionDecision? TryParseDecision(string? value) => value switch {
        "ask" => SitePermissionDecision.Ask,
        "grantForSession" => SitePermissionDecision.GrantForSession,
        "denyForSession" => SitePermissionDecision.DenyForSession,
        "grantPersistently" => SitePermissionDecision.GrantPersistently,
        "denyPersistently" => SitePermissionDecision.DenyPersistently,
        _ => null
    };

    public static SitePermissionDecision ParseDecision(string? value) =>
        TryParseDecision(value) ?? throw new ProtocolException(ProtocolErrorCodes.InvalidPermissionDecision);

    public static MediaPermission Media(string? value) => value switch {
        "camera" => MediaPermission.Camera,
        "microphone" => MediaPermission.Microphone,
        "cameraAndMicrophone" => MediaPermission.CameraAndMicrophone,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidMediaPermission)
    };

    /// An origin the platform reported; the domain lowercases it and fills
    /// in the default web port.
    public static SiteOrigin Origin(JsonElement request, string field) {
        var value = request.GetProperty(field);
        Protocol.Members(value, Scheme, Host, Port);
        return new(Protocol.Text(value, Scheme, SiteOrigin.MaximumSchemeLength), Protocol.Text(value, Host, SiteOrigin.MaximumHostLength),
            value.GetProperty(Port).GetInt32());
    }

    public static SiteOrigin? OptionalOrigin(JsonElement request, string field) =>
        request.TryGetProperty(field, out var value) && value.ValueKind != JsonValueKind.Null ? Origin(request, field) : null;

    /// A saved decision as its persisted spelling.
    public static SitePermissionDecision Decision(JsonElement request, string field) =>
        ParseDecision(Protocol.Text(request, field, 64));

    public static BlockedPopupEvent PopupEvent(string value) => value switch {
        "blocked" => BlockedPopupEvent.Blocked,
        "permission_allowed" => BlockedPopupEvent.PermissionAllowed,
        "permission_blocked_again" => BlockedPopupEvent.PermissionBlockedAgain,
        "navigation" => BlockedPopupEvent.Navigation,
        "popup_allowed" => BlockedPopupEvent.PopupAllowed,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPopupEvent)
    };

    public static BlockedPopupStatus? ParsePopupStatus(string? value) => value switch {
        null => null,
        "blocked" => BlockedPopupStatus.Blocked,
        "allowedAwaitingRetry" => BlockedPopupStatus.AllowedAwaitingRetry,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidStatus)
    };

    /// A page's popup notice as the native store keeps it. A status and an
    /// origin come together or not at all.
    public static BlockedPopupPageState PopupState(JsonElement value) {
        Protocol.Members(value, "status", OriginField, "documentIdentifier", "indicationRevision");
        var status = ParsePopupStatus(Protocol.OptionalText(value, "status", 64));
        var origin = OptionalOrigin(value, OriginField);
        if ((status is null) != (origin is null)) throw new BrowserRuleException(BrowserRuleCodes.InvalidBlockedPopup);
        return new(status, origin,
            Protocol.OptionalText(value, "documentIdentifier", BlockedPopupPageState.MaximumDocumentIdentifierLength),
            value.GetProperty("indicationRevision").GetInt32());
    }

    #endregion
}
