namespace CrestCore.Domain;

/// Shared browser records describe portable web content, never an engine's
/// internal pages, native documents, files, or extension execution state.
public static class SyncContentPolicy
{
    public static bool Includes(string? url) => url is not null
        && Uri.TryCreate(url, UriKind.Absolute, out var parsed)
        && parsed.Scheme is "http" or "https" && parsed.Host.Length > 0;

    public static bool IncludesTab(string? url, bool native, string? savedUrl)
        => !native && Includes(url) && (savedUrl is null || Includes(savedUrl));

    // Receiving a record changes its local presentation to "synced", not the
    // original cause recorded by the device that archived it.
    public static string ProjectArchiveReason(string reason, string? existingReason = null) => reason switch
    {
        "synced" => existingReason is null or "synced" ? "closed" : ProjectArchiveReason(existingReason),
        "deletedOnAnotherDevice" => "deleted",
        _ => reason
    };

    public static string ArchiveReason(string storedReason, string? deletionOrigin) => deletionOrigin switch
    { "local" => "deleted", "remote" => "deletedOnAnotherDevice", _ => storedReason };
}

public readonly record struct SyncPreferences(bool SavedStructure, bool CurrentTabs, bool HistoryAndArchive)
{
    public bool Includes(TabPlacement placement) => placement == TabPlacement.Current ? CurrentTabs : SavedStructure;
}
