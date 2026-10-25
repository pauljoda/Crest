using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CrestCore.Contracts;

/// A validated native snapshot: its content-addressed cache key, WebKit JSON,
/// and source version. Snapshot data never contains executable filtering code.
public sealed record ContentRuleList(string Identifier, string Source, long Version) {
    #region Static Variables

    public const int MaximumArchiveBytes = 4 * 1024 * 1024;
    private const int MaximumSnapshotBytes = 64 * 1024 * 1024;
    private const int MaximumRules = 150000;

    #endregion

    #region Actions - Snapshots

    public static ContentRuleList FromArchive(byte[] archive) {
        ArgumentNullException.ThrowIfNull(archive);
        if (archive.Length > MaximumArchiveBytes)
            throw new ArgumentException("The content-blocking archive is too large.", nameof(archive));
        using var input = new MemoryStream(archive, writable: false);
        using var compressed = new GZipStream(input, CompressionMode.Decompress);
        using var output = new MemoryStream();
        var buffer = new byte[65536];
        int count;
        while ((count = compressed.Read(buffer)) != 0) {
            if (output.Length + count > MaximumSnapshotBytes)
                throw new InvalidDataException("The content-blocking snapshot is too large.");
            output.Write(buffer, 0, count);
        }
        return FromSnapshot(new UTF8Encoding(false, true).GetString(output.GetBuffer(), 0, checked((int)output.Length)));
    }

    public static ContentRuleList FromSnapshot(string snapshot) {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (Encoding.UTF8.GetByteCount(snapshot) > MaximumSnapshotBytes)
            throw new ArgumentException("The content-blocking snapshot is too large.", nameof(snapshot));
        using var document = JsonDocument.Parse(snapshot, new JsonDocumentOptions { MaxDepth = 16 });
        var root = document.RootElement;
        var version = root.GetProperty("version").GetInt64();
        var rules = root.GetProperty("rules");
        if (version <= 0 || rules.ValueKind != JsonValueKind.Array || rules.GetArrayLength() is < 1 or > MaximumRules)
            throw new ArgumentException("The content-blocking snapshot is invalid.", nameof(snapshot));
        // The rule objects are an opaque WebKit payload. Restrict actions to
        // declarative blocking/hiding, then let WebKit validate their syntax.
        foreach (var rule in rules.EnumerateArray()) {
            var action = rule.GetProperty("action").GetProperty("type").GetString();
            if (action is not ("block" or "css-display-none" or "ignore-previous-rules"))
                throw new ArgumentException("The snapshot contains an unsupported action.", nameof(snapshot));
            var trigger = rule.GetProperty("trigger");
            if (string.IsNullOrWhiteSpace(trigger.GetProperty("url-filter").GetString()))
                throw new ArgumentException("The snapshot contains an empty URL filter.", nameof(snapshot));
            if (action == "block" && (!trigger.TryGetProperty("resource-type", out var resources)
                || resources.ValueKind != JsonValueKind.Array || resources.GetArrayLength() == 0
                || resources.EnumerateArray().Any(resource => resource.GetString() == "document")))
                throw new ArgumentException("Content blocking cannot block top-level documents.", nameof(snapshot));
        }
        var source = rules.GetRawText();
        var digest = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(source)));
        return new($"com.pauldavis.crest.content-blocking.balanced.v3.{digest}", source, version);
    }

    #endregion
}
