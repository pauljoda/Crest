using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// <summary>
/// What the requesting window shows, as read-only command context. Selection is
/// UI state: the core reads it to decide follow-up hints (the tab to show after
/// the viewed tab closes, the tab a cleanup sweep must keep), and never stores it.
/// Wire shape: <c>{"spaceId": uuid|null, "tabs": [{"spaceId": uuid, "tabId": uuid|null}]}</c>.
/// </summary>
internal sealed record SessionView(Guid? SpaceId, IReadOnlyDictionary<Guid, Guid?> Tabs) {
    #region Variables

    public const string Key = "view";

    public static readonly SessionView Empty = new(null, new Dictionary<Guid, Guid?>());

    #endregion

    #region Actions - Decoding

    /// An absent view is a command issued without a window, which has nothing
    /// on screen for a hint to preserve.
    public static SessionView Decode(JsonNode? value) {
        if (value is null) return Empty;
        if (value is not JsonObject view) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedSelection);
        var tabs = new Dictionary<Guid, Guid?>();
        foreach (var entry in view["tabs"] as JsonArray ?? []) {
            if (entry is not JsonObject item) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedSelection);
            var spaceId = NativeSessionAuthority.Id(item["spaceId"]);
            if (!tabs.TryAdd(spaceId, item["tabId"] is { } tab ? NativeSessionAuthority.Id(tab) : null))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedSelection);
        }
        return new(view["spaceId"] is { } space ? NativeSessionAuthority.Id(space) : null, tabs);
    }

    #endregion

    #region Mutators

    public Guid? Tab(Guid space) => Tabs.GetValueOrDefault(space);

    #endregion
}
