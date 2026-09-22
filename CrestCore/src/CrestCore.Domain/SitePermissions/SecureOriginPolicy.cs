namespace CrestCore.Domain;

/// Powerful features (location, hosted web notifications) need a secure
/// context: HTTPS, or plain HTTP only on this device's loopback names.
public static class SecureOriginPolicy {
    #region Actions - Origins

    public static bool Allows(SiteOrigin origin) {
        ArgumentNullException.ThrowIfNull(origin);
        if (origin.Scheme == "https") return true;
        return origin.Scheme == "http" && origin.Host is "localhost" or "127.0.0.1" or "::1";
    }

    #endregion
}
