using System.Text.Json.Nodes;

namespace CrestCore.Application;

/// <summary>
/// A follow-up selection the core suggests after a command: the Space the
/// requesting window may switch to, and the tab it may show in each Space whose
/// viewed tab the command changed (null to show none). The window applies it to
/// its own selection or ignores it; the core keeps no copy. Wire shape:
/// <c>{"spaceId": uuid|null, "tabs": [{"spaceId": uuid, "tabId": uuid|null}]}</c>.
/// </summary>
internal sealed class SessionSelectionHint {
    #region Variables

    public const string Key = "selection";

    private readonly Dictionary<Guid, Guid?> tabs = [];

    public Guid? SpaceId { get; private set; }

    public IReadOnlyDictionary<Guid, Guid?> Tabs => tabs;

    #endregion

    #region Actions - Suggestions

    public SessionSelectionHint SelectSpace(Guid space) { SpaceId = space; return this; }

    /// Suggests a tab for a Space. Nothing is suggested when the window already
    /// shows it, so an unrelated command leaves the window's selection alone.
    public SessionSelectionHint SelectTab(SessionView view, Guid space, Guid? tab) {
        if (view.Tab(space) == tab) tabs.Remove(space);
        else tabs[space] = tab;
        return this;
    }

    #endregion

    #region Actions - Encoding

    public JsonObject Encode() => new() {
        ["spaceId"] = SpaceId?.ToString("D"),
        ["tabs"] = new JsonArray(tabs.Select(pair => (JsonNode)new JsonObject {
            ["spaceId"] = pair.Key.ToString("D"),
            ["tabId"] = pair.Value?.ToString("D")
        }).ToArray())
    };

    #endregion
}
