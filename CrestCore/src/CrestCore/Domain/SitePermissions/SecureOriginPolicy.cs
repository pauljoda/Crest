using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Powerful features (location, hosted web notifications) need a secure
/// context: HTTPS, or plain HTTP only on this device's loopback names.
public static class SecureOriginPolicy {
    #region Actions - Origins

    /// An origin the rules cannot read is never secure.
    public static bool Allows(SiteOrigin origin) {
        ArgumentNullException.ThrowIfNull(origin);
        if (!origin.IsValid || WebScheme.Named(origin.Scheme) is not { } scheme) return false;
        return scheme.IsSecure || origin.Host is "localhost" or "127.0.0.1" or "::1";
    }

    #endregion
}
