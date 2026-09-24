namespace CrestCore.Domain;

/// Which schemes the engine keeps, which nothing may load, and which belong
/// to another application.
public static class ExternalSchemePolicy {
    #region Variables

    public const int MaximumSchemeLength = 256;

    /// Schemes the engine itself must keep. `data:` is here rather than blocked
    /// because the engine, not Crest, refuses a top-level `data:` navigation
    /// from web content; handing one to another app would walk around that.
    private static readonly HashSet<string> EngineSchemes = new(StringComparer.Ordinal) {
        "http", "https", "about", "blob", "chrome-extension", "crest-extension", "data", "webkit-extension"
    };

    /// Schemes that may never load and may never reach another application.
    private static readonly HashSet<string> BlockedSchemes = new(StringComparer.Ordinal) { "javascript" };

    #endregion

    #region Actions - Schemes

    /// A request the engine built without a scheme stays the engine's to
    /// resolve. `file:` is kept only for a load Crest itself initiated: web
    /// content asking for a file URL is asking to read the person's disk.
    public static ExternalSchemeDisposition Disposition(string? scheme, bool isAppInitiated) {
        if (string.IsNullOrEmpty(scheme)) return ExternalSchemeDisposition.Engine;
        if (scheme.Length > MaximumSchemeLength) return ExternalSchemeDisposition.Blocked;
        string normalized = scheme.ToLowerInvariant();
        if (EngineSchemes.Contains(normalized)) return ExternalSchemeDisposition.Engine;
        if (BlockedSchemes.Contains(normalized)) return ExternalSchemeDisposition.Blocked;
        if (normalized == "file") return isAppInitiated ? ExternalSchemeDisposition.Engine : ExternalSchemeDisposition.Blocked;
        return ExternalSchemeDisposition.HandOff;
    }

    #endregion
}
