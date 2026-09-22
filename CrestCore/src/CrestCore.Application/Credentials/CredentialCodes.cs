using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the credential and passkey policy operations. They match
/// the native projection's case names.
internal static class CredentialCodes {
    #region Variables

    public const int MaximumUsernameLength = 4_096;

    #endregion

    #region Actions - Encoding

    public static string Action(CredentialCaptureAction action) => action switch {
        CredentialCaptureAction.RememberUsername => "rememberUsername",
        CredentialCaptureAction.DismissFill => "dismissFill",
        CredentialCaptureAction.OfferFill => "offerFill",
        CredentialCaptureAction.CaptureCandidate => "captureCandidate",
        CredentialCaptureAction.OfferSave => "offerSave",
        CredentialCaptureAction.KeepPending => "keepPending",
        CredentialCaptureAction.DiscardPending => "discardPending",
        _ => "ignore"
    };

    public static string Source(CredentialUsernameSource source) => source switch {
        CredentialUsernameSource.Explicit => "explicit",
        CredentialUsernameSource.Hint => "hint",
        _ => "none"
    };

    public static string Validity(CredentialSaveValidity validity) => validity switch {
        CredentialSaveValidity.Accepted => "accepted",
        CredentialSaveValidity.InsecureOrigin => "insecureOrigin",
        _ => "stale"
    };

    public static string Plan(CredentialSavePlanKind kind) => kind switch {
        CredentialSavePlanKind.Update => "update",
        CredentialSavePlanKind.AlreadyStored => "alreadyStored",
        _ => "create"
    };

    public static string Status(PasskeyAccessStatus status) => status switch {
        PasskeyAccessStatus.ManagedCapabilityRequired => "managedCapabilityRequired",
        PasskeyAccessStatus.DeviceNotConfigured => "deviceNotConfigured",
        PasskeyAccessStatus.Authorized => "authorized",
        PasskeyAccessStatus.Denied => "denied",
        _ => "notDetermined"
    };

    public static string Availability(SystemPasswordWriteThroughAvailability availability) => availability switch {
        SystemPasswordWriteThroughAvailability.Available => "available",
        SystemPasswordWriteThroughAvailability.IsolatedLaunch => "isolatedLaunch",
        SystemPasswordWriteThroughAvailability.SystemVersionRequired => "systemVersionRequired",
        SystemPasswordWriteThroughAvailability.ManagedBrowserCapabilityRequired => "managedBrowserCapabilityRequired",
        _ => "unsupportedPlatform"
    };

    #endregion

    #region Actions - Decoding

    public static CredentialCaptureEvent ParseEvent(string? value) => value switch {
        "username" => CredentialCaptureEvent.Username,
        "focus" => CredentialCaptureEvent.Focus,
        "submit" => CredentialCaptureEvent.Submit,
        "documentState" => CredentialCaptureEvent.DocumentState,
        "filled" => CredentialCaptureEvent.Filled,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidCredentialEvent)
    };

    public static CredentialPasswordKind ParseKind(string? value) => value switch {
        "current" => CredentialPasswordKind.Current,
        "new" => CredentialPasswordKind.New,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPasswordKind)
    };

    public static CredentialFillSource ParseSource(string? value) => value switch {
        "saved" => CredentialFillSource.Saved,
        "generated" => CredentialFillSource.Generated,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidFillSource)
    };

    public static PasskeyDeviceConfiguration ParseConfiguration(string? value) => value switch {
        "configured" => PasskeyDeviceConfiguration.Configured,
        "notConfigured" => PasskeyDeviceConfiguration.NotConfigured,
        "unknown" => PasskeyDeviceConfiguration.Unknown,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPasskeyState)
    };

    public static PasskeyAuthorizationState ParseAuthorization(string? value) => value switch {
        "authorized" => PasskeyAuthorizationState.Authorized,
        "denied" => PasskeyAuthorizationState.Denied,
        "notDetermined" => PasskeyAuthorizationState.NotDetermined,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidPasskeyState)
    };

    public static SystemPasswordWriteThroughAvailability ParseAvailability(string? value) => value switch {
        "available" => SystemPasswordWriteThroughAvailability.Available,
        "unsupportedPlatform" => SystemPasswordWriteThroughAvailability.UnsupportedPlatform,
        "isolatedLaunch" => SystemPasswordWriteThroughAvailability.IsolatedLaunch,
        "systemVersionRequired" => SystemPasswordWriteThroughAvailability.SystemVersionRequired,
        "managedBrowserCapabilityRequired" => SystemPasswordWriteThroughAvailability.ManagedBrowserCapabilityRequired,
        _ => throw new ProtocolException(ProtocolErrorCodes.InvalidWriteThroughAvailability)
    };

    public static CredentialOrigin Origin(JsonElement request, string field) {
        var value = request.GetProperty(field);
        Protocol.Members(value, "scheme", "host", "port");
        return new(Protocol.Text(value, "scheme", 5), Protocol.Text(value, "host", CredentialOrigin.MaximumHostLength),
            value.GetProperty("port").GetInt32());
    }

    public static CredentialRecord Record(JsonElement value, bool includesUsername) {
        if (includesUsername) Protocol.Members(value, "id", "username", "updatedAt", "lastUsedAt");
        else Protocol.Members(value, "id", "updatedAt", "lastUsedAt");
        return new(Protocol.Id(value, "id"), includesUsername ? DownloadCodes.AnyText(value, "username", MaximumUsernameLength) : null,
            value.GetProperty("updatedAt").GetDouble(), DownloadCodes.Optional(value, "lastUsedAt")?.GetDouble());
    }

    #endregion
}
