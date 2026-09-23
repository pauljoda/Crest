namespace CrestCore.Domain;

/// Crest's site identity for a host: a leading `www.` names the same site as
/// the bare host, while every other subdomain stays distinct.
public static class SiteHost {
    #region Variables

    private const string WwwPrefix = "www.";

    #endregion

    #region Actions - Normalization

    /// The host without one leading `www.`. Case is left to the caller, which
    /// may have lowercased or IDN-encoded the host first.
    public static string WithoutWww(string host)
        => host.StartsWith(WwwPrefix, StringComparison.Ordinal) ? host[WwwPrefix.Length..] : host;

    #endregion
}
