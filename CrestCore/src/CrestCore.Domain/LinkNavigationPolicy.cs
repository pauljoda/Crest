namespace CrestCore.Domain;

public enum LinkNavigationDecision { Navigate, PeekModifier, PeekSavedSite, BackgroundTab, ForegroundTab }
public enum LinkPeekModifier { Option, Command }

/// Semantic link behavior shared by the native engine adapters. Engines keep
/// ownership of request security, downloads, form submissions and rendering.
public static class LinkNavigationPolicy
{
    public static (bool Peek, bool NewTab) Modifiers(bool command, bool option, bool middle, LinkPeekModifier preference)
    {
        bool peek = preference == LinkPeekModifier.Command ? command : option;
        bool newTab = preference == LinkPeekModifier.Command ? option : command;
        return (peek, (!peek && newTab) || middle);
    }
    public static LinkNavigationDecision Decide(string? destination, bool userActivatedLink,
        bool topLevel, bool peekModified, bool newTabModified, bool shiftModified,
        bool focusesNewTabs, bool hasContext, string? placement, string? savedUrl,
        bool automaticallyOpensPeek)
    {
        if (!userActivatedLink || !TryWebUrl(destination, out var target)) return LinkNavigationDecision.Navigate;
        if (topLevel && hasContext && peekModified) return LinkNavigationDecision.PeekModifier;
        if (newTabModified)
            return focusesNewTabs != shiftModified ? LinkNavigationDecision.ForegroundTab : LinkNavigationDecision.BackgroundTab;
        if (topLevel && hasContext && automaticallyOpensPeek && placement is "pinned" or "saved"
            && TryWebUrl(savedUrl, out var saved) && NormalizeHost(saved!) != NormalizeHost(target!))
            return LinkNavigationDecision.PeekSavedSite;
        return LinkNavigationDecision.Navigate;
    }

    private static bool TryWebUrl(string? value, out Uri? url) =>
        Uri.TryCreate(value, UriKind.Absolute, out url) && url.Scheme is "http" or "https" && url.Host.Length > 0;

    // Match Crest's saved-site contract: ignore www, but keep other subdomains
    // distinct. IdnHost also compares Unicode and punycode URL spellings equally.
    private static string NormalizeHost(Uri url)
    {
        string host = url.IdnHost.ToLowerInvariant();
        return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
    }
}
