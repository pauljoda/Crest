using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// File persistence and restoration of downloaded filter lists and state for
/// `FilterLibrary`.
internal sealed partial class FilterLibrary {
    #region Actions - Storage

    private string? ReadText(string name) {
        if (folder is null) {
            lock (gate) return heldTexts.GetValueOrDefault(name);
        }
        try {
            return File.ReadAllText(Path.Combine(folder, "lists", name + ".txt"));
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            return null;
        }
    }

    /// Keeps a download's text, unless the library closed. The caller holds
    /// the lock.
    private void WriteText(string name, byte[] bytes, string text) {
        if (folder is null) heldTexts[name] = text;
        else if (!closed) WriteAtomically(Path.Combine(folder, "lists", name + ".txt"), bytes);
    }

    private static void WriteAtomically(string path, byte[] bytes) {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string pending = path + ".pending";
        File.WriteAllBytes(pending, bytes);
        File.Move(pending, path, overwrite: true);
    }

    /// Writes every copy's state, and the rules in force, unless the library
    /// closed. The caller holds the lock.
    private void SaveState() {
        if (folder is null || closed) return;
        var lists = new JsonObject();
        foreach (var (name, copy) in copies)
            lists[name] = copy.Encoded();
        try {
            WriteAtomically(Path.Combine(folder, "state.json"), Encoding.UTF8.GetBytes(new JsonObject { ["lists"] = lists }.ToJsonString()));
            if (publishedKey is not null)
                WriteAtomically(Path.Combine(folder, "rules", publishedKey + ".count"),
                    Encoding.UTF8.GetBytes(published.Identifiers.Count.ToString(System.Globalization.CultureInfo.InvariantCulture)));
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException) {
            // The copies stay in memory; the next save writes them.
        }
    }

    /// Reads what a previous launch kept. A copy whose text is gone, or a
    /// state that does not read, starts the list over.
    private void RestoreState() {
        if (folder is null) return;
        JsonObject? lists;
        try {
            lists = JsonNode.Parse(File.ReadAllText(Path.Combine(folder, "state.json")))?["lists"] as JsonObject;
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException) {
            return;
        }
        foreach (var (name, value) in lists ?? []) {
            bool known = FilterList.Named(name) is not null || name == ResourcesName || name == LinkTrackingName
                || name.StartsWith("custom-", StringComparison.Ordinal);
            if (!known || value is not JsonObject state) continue;
            if (Copy.DigestIn(state) is not null && !File.Exists(Path.Combine(folder, "lists", name + ".txt"))) continue;
            copies[name] = Copy.Decoded(state, UsualRefresh);
        }
    }

    #endregion
}
