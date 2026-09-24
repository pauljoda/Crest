namespace CrestCore.Domain;

/// Shared browser records describe portable web content, never an engine's
/// internal pages, native documents, files, or extension execution state.
public static class SyncContentPolicy {
    #region Actions - Sync

    public static bool Includes(string? url) => url is not null
        && Uri.TryCreate(url, UriKind.Absolute, out var parsed)
        && (parsed.Scheme == Uri.UriSchemeHttp || parsed.Scheme == Uri.UriSchemeHttps)
        && parsed.Host.Length > 0;

    public static bool IncludesTab(string? url, bool native, string? savedUrl)
        => !native && Includes(url) && (savedUrl is null || Includes(savedUrl));

    #endregion
}
