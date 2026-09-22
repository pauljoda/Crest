namespace CrestCore.Domain;

/// Crest's bundled Balanced protection: third-party network loads from known
/// advertising and analytics hosts, and their subdomains, are blocked. The
/// identifier names the rule list's version; change it with the rules.
public static class BalancedContentBlocking {
    #region Variables

    public const string Identifier = "com.pauldavis.crest.content-blocking.balanced.v2";

    public static readonly IReadOnlyList<string> BlockedHostSuffixes = [
        "doubleclick.net",
        "googleadservices.com",
        "googlesyndication.com",
        "google-analytics.com",
        "googletagmanager.com",
        "ads-twitter.com",
        "analytics.twitter.com",
        "scorecardresearch.com",
        "quantserve.com",
        "hotjar.com",
        "segment.io",
        "segment.com",
        "mixpanel.com",
        "amplitude.com",
        "clarity.ms",
        "nr-data.net",
        "taboola.com",
        "outbrain.com",
        "snap.licdn.com"
    ];

    /// Every resource a page fetches over the network; top-level documents are
    /// never blocked.
    public static readonly IReadOnlyList<string> NetworkResourceTypes = [
        "child-document",
        "image",
        "style-sheet",
        "script",
        "font",
        "raw",
        "svg-document",
        "media",
        "popup",
        "ping",
        "fetch",
        "websocket",
        "csp-report",
        "other"
    ];

    #endregion

    #region Actions - Rules

    /// The URL filter for one host suffix: any scheme, the host itself or any
    /// subdomain, followed by a port or path.
    public static string UrlFilter(string hostSuffix) => $"^[^:]+://+([^:/]+\\.)?{hostSuffix.Replace(".", "\\.", StringComparison.Ordinal)}[:/]";

    #endregion
}
