using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Which schemes the engine keeps, which nothing may load, and which belong
/// to another application.
public static class ExternalSchemePolicy {
    #region Variables

    public const int MaximumSchemeLength = 256;

    #endregion

    #region Actions - Schemes

    /// A request the engine built without a scheme stays the engine's to
    /// resolve; one in a scheme Crest decides about goes as the scheme says,
    /// and any other belongs to another application.
    public static ExternalSchemeDisposition Disposition(string? scheme, bool isAppInitiated) {
        if (string.IsNullOrEmpty(scheme)) return ExternalSchemeDisposition.Engine;
        if (scheme.Length > MaximumSchemeLength) return ExternalSchemeDisposition.Blocked;
        if (UrlScheme.Named(scheme.ToLowerInvariant()) is not { } known) return ExternalSchemeDisposition.HandOff;
        return isAppInitiated ? known.AppInitiatedDisposition : known.Disposition;
    }

    #endregion
}
