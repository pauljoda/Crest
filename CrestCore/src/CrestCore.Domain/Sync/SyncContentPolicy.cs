using System.Text;

namespace CrestCore.Domain;

/// Shared browser records describe portable web content, never an engine's
/// internal pages, native documents, files, or extension execution state. An
/// address every client reads is http or https, names a host and fits in
/// `MaximumAddressBytes` of UTF-8; a record whose address does not stays on
/// this device.
public static class SyncContentPolicy {
    #region Static Variables

    /// The longest address, in UTF-8 bytes, every client reads in a record.
    public const int MaximumAddressBytes = 8_192;

    #endregion

    #region Actions - Sync

    public static bool Includes(string? url) => url is not null
        && Encoding.UTF8.GetByteCount(url) <= MaximumAddressBytes
        && Uri.TryCreate(url, UriKind.Absolute, out var parsed)
        && (parsed.Scheme == Uri.UriSchemeHttp || parsed.Scheme == Uri.UriSchemeHttps)
        && parsed.Host.Length > 0;

    public static bool IncludesTab(string? url, bool native, string? savedUrl)
        => !native && Includes(url) && (savedUrl is null || Includes(savedUrl));

    #endregion
}
