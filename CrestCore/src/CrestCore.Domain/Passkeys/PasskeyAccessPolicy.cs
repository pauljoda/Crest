using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Passkey access for websites, and the write-through of Crest-saved passwords
/// to the system's Passwords app. The platform supplies build, device and
/// authorization facts; these rules decide what Crest may do with them.
public static class PasskeyAccessPolicy {
    #region Actions - Passkeys

    /// The managed capability comes first, then device setup, then consent.
    public static PasskeyAccessStatus Status(bool hasManagedCapability, PasskeyDeviceConfiguration deviceConfiguration,
        PasskeyAuthorizationState authorizationState) {
        if (!hasManagedCapability) return PasskeyAccessStatus.ManagedCapabilityRequired;
        if (deviceConfiguration == PasskeyDeviceConfiguration.NotConfigured) return PasskeyAccessStatus.DeviceNotConfigured;
        return authorizationState switch {
            PasskeyAuthorizationState.Authorized => PasskeyAccessStatus.Authorized,
            PasskeyAuthorizationState.Denied => PasskeyAccessStatus.Denied,
            _ => PasskeyAccessStatus.NotDetermined
        };
    }

    #endregion

    #region Actions - System passwords

    /// Write-through is a mobile feature. An isolated launch never reaches the
    /// person's system password store, whatever the build can do.
    public static SystemPasswordWriteThroughAvailability WriteThroughAvailability(bool isMobilePlatform,
        bool supportsSystemApi, bool hasManagedBrowserCapability, bool isLaunchIsolated) {
        if (!isMobilePlatform) return SystemPasswordWriteThroughAvailability.UnsupportedPlatform;
        if (isLaunchIsolated) return SystemPasswordWriteThroughAvailability.IsolatedLaunch;
        if (!supportsSystemApi) return SystemPasswordWriteThroughAvailability.SystemVersionRequired;
        return hasManagedBrowserCapability
            ? SystemPasswordWriteThroughAvailability.Available
            : SystemPasswordWriteThroughAvailability.ManagedBrowserCapabilityRequired;
    }

    /// Offered only after the Space opts in, when available, and never from a
    /// private window.
    public static bool OffersWriteThrough(bool spaceOffersSystemPasswords, SystemPasswordWriteThroughAvailability availability,
        bool isPrivateBrowsing) =>
        spaceOffersSystemPasswords && availability == SystemPasswordWriteThroughAvailability.Available && !isPrivateBrowsing;

    #endregion
}
