namespace CrestCore.Domain;

/// Shared browser records describe portable web content, never an engine's
/// internal pages, native documents, files, or extension execution state. An
/// address every client reads is http or https, names a host and, spelled as
/// every client parses it, fits in `SyncedAddress.MaximumBytes` of UTF-8; a
/// record whose address does not stays on this device.
public static class SyncContentPolicy {
    #region Actions - Sync

    public static bool Includes(string? url) => url is not null && new SyncedAddress(url).IsPortable;

    public static bool IncludesTab(string? url, bool native, string? savedUrl)
        => !native && Includes(url) && (savedUrl is null || Includes(savedUrl));

    #endregion
}
