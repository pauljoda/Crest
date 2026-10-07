using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Semantic link behavior shared by the native engine adapters. Engines keep
/// ownership of request security, downloads, form submissions and rendering.
public static class LinkNavigationPolicy {
    #region Actions - Navigation

    public static LinkNavigationDecision Decide(string? destination, bool userActivatedLink,
        bool topLevel, bool peekModified, bool newTabModified, bool shiftModified,
        bool focusesNewTabs, bool hasContext, TabPlacement? placement, string? savedUrl,
        bool automaticallyOpensPeek) {
        if (!userActivatedLink || !TryWebUrl(destination, out var target)) return LinkNavigationDecision.Navigate;
        if (topLevel && hasContext && peekModified) return LinkNavigationDecision.PeekModifier;
        if (newTabModified)
            return focusesNewTabs != shiftModified ? LinkNavigationDecision.ForegroundTab : LinkNavigationDecision.BackgroundTab;
        if (topLevel && hasContext && automaticallyOpensPeek && placement?.IsDurable == true
            && TryWebUrl(savedUrl, out var saved) && NormalizeHost(saved!) != NormalizeHost(target!))
            return LinkNavigationDecision.PeekSavedSite;
        return LinkNavigationDecision.Navigate;
    }

    /// Whether a window a page opened comes to the front: an ordinary
    /// new-window request does, and one made with the new-tab gesture follows
    /// the person's choice, which Shift reverses.
    public static bool SelectsOpenedWindow(bool newTabGesture, bool shiftModified, bool focusesNewTabs) =>
        !newTabGesture || focusesNewTabs != shiftModified;

    private static bool TryWebUrl(string? value, out Uri? url) =>
        Uri.TryCreate(value, UriKind.Absolute, out url)
        && WebScheme.Named(url.Scheme) is not null && url.Host.Length > 0;

    // Match Crest's saved-site contract: ignore www, but keep other subdomains
    // distinct. IdnHost also compares Unicode and punycode URL spellings equally.
    private static string NormalizeHost(Uri url) => SiteHost.WithoutWww(url.IdnHost.ToLowerInvariant());

    #endregion
}
