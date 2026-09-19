using System.Text.Json.Nodes;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class BrowserKernel
{
    private void QueryRecords(Envelope m)
    {
        var p = m.Payload;
        Protocol.Members(p, "windowId", "spaceId", "kind", "queryId", "query", "offset");
        var window = workspace.Window(new(Protocol.Id(p, "windowId")));
        var space = workspace.Space(new(Protocol.Id(p, "spaceId"))); space.EnsureAccessible();
        if (window.SpaceId != space.Id) throw new BrowserRuleException("space_not_selected");
        var kind = Protocol.Text(p, "kind", 32);
        var query = p.TryGetProperty("query", out var text) ? text.GetString()?.Trim() ?? "" : "";
        if (query.Length > 512) throw new BrowserRuleException("invalid_query");
        var queryId = Protocol.Id(p, "queryId");
        var offset = p.GetProperty("offset").GetInt32();
        if (offset < 0) throw new BrowserRuleException("invalid_offset");
        bool Matches(string title, string? url) => title.Contains(query, StringComparison.OrdinalIgnoreCase)
            || url?.Contains(query, StringComparison.OrdinalIgnoreCase) == true;
        static string Bounded(string value, int maximum) => value.Length <= maximum ? value : value[..maximum];
        IEnumerable<(Guid Id, string Title, string? Url, DateTimeOffset Date, int Count)> records = kind switch
        {
            "history" => space.History.Select(h => (h.Id, h.Title, (string?)h.Url, h.VisitedAt, h.VisitCount)),
            "archive" => space.Archive.Select(a => (a.Id.Value, a.Tab.CustomTitle ?? a.Tab.Title, a.Tab.Url, a.ClosedAt, 1)),
            _ => throw new BrowserRuleException("invalid_native_kind")
        };
        var matching = records.Where(r => Matches(r.Title, r.Url)).ToArray();
        var items = new JsonArray(matching.Skip(offset).Take(50).Select(r => (JsonNode)new JsonObject
        {
            ["id"] = r.Id.ToString(), ["title"] = Bounded(r.Title, 512),
            ["url"] = r.Url is null ? null : Bounded(r.Url, 2048),
            ["date"] = r.Date.ToUnixTimeSeconds(), ["visitCount"] = r.Count
        }).ToArray());
        // Read results do not advance or persist semantic state. Query identity
        // lets the native UI discard replies for superseded searches or panes.
        Emit(m, ui, "result", "ui.records", new()
        {
            ["workspaceId"] = workspace.Id.Value.ToString(), ["spaceId"] = space.Id.Value.ToString(),
            ["windowId"] = window.Id.Value.ToString(), ["queryId"] = queryId.ToString(), ["kind"] = kind,
            ["offset"] = offset, ["total"] = matching.Length, ["items"] = items
        });
    }
}
