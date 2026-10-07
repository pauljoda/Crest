using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What another application, a drop, a peek, a popup or a context-menu item
/// may hand Crest as a link, and what Crest opens as a local document.
public static class ExternalUrlPolicy {
    #region Static Variables

    /// The longest host a platform-parsed address may report; a longer one is
    /// refused.
    public const int MaximumHostLength = 1_024;

    #endregion

    #region Actions - Links

    /// A web link: HTTP or HTTPS with a host. Everything else is refused, so a
    /// page or another app cannot steer Crest at local paths or other schemes.
    public static bool AcceptsWebLink(string? scheme, string? host) =>
        host is { Length: > 0 and <= MaximumHostLength } && WebScheme.Spelled(scheme) is not null;

    /// A local document opened as a document (Finder, Open With, the Open
    /// panel), never as a web link. Remote authorities are refused;
    /// `file://localhost/…` is this device spelled the long way round.
    public static bool AcceptsLocalDocument(LocalDocumentFacts facts) {
        ArgumentNullException.ThrowIfNull(facts);
        if (!facts.IsFile || facts.HasUser || !facts.HasPath || facts.Host is { Length: > MaximumHostLength }) return false;
        return string.IsNullOrEmpty(facts.Host) || string.Equals(facts.Host, "localhost", StringComparison.OrdinalIgnoreCase);
    }

    #endregion
}
