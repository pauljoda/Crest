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

    #endregion
}
