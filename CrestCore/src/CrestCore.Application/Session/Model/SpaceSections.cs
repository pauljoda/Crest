using System.Collections;
using System.Text.Json.Nodes;

namespace CrestCore.Application;

/// <summary>Typed record collections in a Space snapshot. Named enumeration serves the JSON boundary.</summary>
internal sealed record SpaceSections(IReadOnlyList<JsonNode> Tabs, IReadOnlyList<JsonNode> Folders,
    IReadOnlyList<JsonNode> History, IReadOnlyList<JsonNode> ArchivedTabs)
    : IReadOnlyDictionary<string, IReadOnlyList<JsonNode>> {
    internal static readonly IReadOnlyList<string> Names = Array.AsReadOnly<string>(["tabs", "folders", "history", "archivedTabs"]);

    public IReadOnlyList<JsonNode> this[string key] => key switch {
        "tabs" => Tabs,
        "folders" => Folders,
        "history" => History,
        "archivedTabs" => ArchivedTabs,
        _ => throw new KeyNotFoundException(key)
    };

    public IEnumerable<string> Keys => Names;
    public IEnumerable<IReadOnlyList<JsonNode>> Values => Names.Select(name => this[name]);
    public int Count => Names.Count;
    public bool ContainsKey(string key) => Names.Contains(key, StringComparer.Ordinal);

    public bool TryGetValue(string key, out IReadOnlyList<JsonNode> value) {
        if (ContainsKey(key)) {
            value = this[key];
            return true;
        }
        value = Array.Empty<JsonNode>();
        return false;
    }

    public IEnumerator<KeyValuePair<string, IReadOnlyList<JsonNode>>> GetEnumerator()
        => Names.Select(name => new KeyValuePair<string, IReadOnlyList<JsonNode>>(name, this[name])).GetEnumerator();

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}
