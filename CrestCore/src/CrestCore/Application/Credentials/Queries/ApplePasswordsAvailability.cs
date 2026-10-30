using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether Apple Passwords may be used, and the helper started, for this
/// launch, window and Space. The first failing fact wins. Isolation and private
/// browsing are decided before any helper fact, so neither can ever start the
/// helper. When Apple Passwords is available and Apple's own extension is on in
/// the Space, Crest's rows win and it offers to turn the extension off.
public sealed record ApplePasswordsAvailability(bool IsMacPlatform, bool HasManagedBrowserCapability, bool IsLaunchIsolated,
    bool IsPrivateBrowsing, bool SpaceCredentialsEnabled, bool SpaceUsesApplePasswords, bool ApplePasswordsExtensionEnabled,
    ApplePasswordsHelperFact Helper) : Query<ApplePasswordsSupport> {
    #region Variables

    internal ApplePasswordsStatus Status {
        get {
            if (!IsMacPlatform) return ApplePasswordsStatus.UnsupportedPlatform;
            if (IsLaunchIsolated) return ApplePasswordsStatus.IsolatedLaunch;
            if (IsPrivateBrowsing) return ApplePasswordsStatus.PrivateWindow;
            if (!HasManagedBrowserCapability) return ApplePasswordsStatus.ManagedBrowserCapabilityRequired;
            if (!SpaceCredentialsEnabled) return ApplePasswordsStatus.CredentialsDisabled;
            if (!SpaceUsesApplePasswords) return ApplePasswordsStatus.TurnedOff;
            return Helper.Status;
        }
    }

    #endregion

    #region Actions - Answering

    internal override ApplePasswordsSupport Answer(CrestApp app) {
        var status = Status;
        return new(status, status.OffersApplePasswords && ApplePasswordsExtensionEnabled);
    }

    #endregion
}
