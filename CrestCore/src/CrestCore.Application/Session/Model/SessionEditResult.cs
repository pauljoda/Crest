using System.Text;
using System.Text.Json.Nodes;

namespace CrestCore.Application;

internal sealed record SessionTabCopy(Guid Source, Guid Copy);

internal sealed record SessionFaviconUpdate(Guid TabId, bool Adopts);

/// <summary>The edited Space and native side effects returned by one session edit.
/// <paramref name="SelectedTabId"/> is the tab the requesting window should show in
/// the edited Space afterwards and <paramref name="SelectSpace"/> whether it should
/// switch to that Space; both are hints for the window, never stored.</summary>
internal sealed record SessionEditResult(JsonNode Space, Guid? TabId, Guid? SelectedTabId, bool SelectSpace,
    IReadOnlyList<SessionTabCopy> Copies, bool Changed, SessionFaviconUpdate? Favicon) {
    #region Actions - Decoding

    public static SessionEditResult Decode(ReadOnlySpan<byte> bytes) {
        var value = JsonNode.Parse(bytes)!.AsObject();
        var favicon = value["favicon"] is JsonObject icon
            ? new SessionFaviconUpdate(Guid.Parse(icon["tabId"]!.GetValue<string>()), icon["adopts"]!.GetValue<bool>())
            : null;
        var copies = value["copies"]!.AsArray().Select(item => new SessionTabCopy(
            Guid.Parse(item!["source"]!.GetValue<string>()), Guid.Parse(item["copy"]!.GetValue<string>()))).ToArray();
        return new(value["space"]!.DeepClone(),
            value["tabId"] is { } tabId ? Guid.Parse(tabId.GetValue<string>()) : null,
            value["selectedTabId"] is { } selected ? Guid.Parse(selected.GetValue<string>()) : null,
            value["selectSpace"]!.GetValue<bool>(), copies, value["changed"]!.GetValue<bool>(), favicon);
    }

    #endregion

    #region Actions - Encoding

    public byte[] Encode() => Encoding.UTF8.GetBytes(Fields().ToJsonString());

    /// The command answer the native caller reads: the edited Space and side
    /// effects with the window's follow-up selection as a hint.
    public byte[] Encode(SessionSelectionHint hint) {
        var value = Fields();
        value.Remove("selectedTabId"); value.Remove("selectSpace");
        value[SessionSelectionHint.Key] = hint.Encode();
        return Encoding.UTF8.GetBytes(value.ToJsonString());
    }

    private JsonObject Fields() => new() {
        ["space"] = Space.DeepClone(),
        ["tabId"] = TabId?.ToString("D"),
        ["selectedTabId"] = SelectedTabId?.ToString("D"),
        ["selectSpace"] = SelectSpace,
        ["copies"] = new JsonArray(Copies.Select(item => (JsonNode)new JsonObject {
            ["source"] = item.Source.ToString("D"),
            ["copy"] = item.Copy.ToString("D")
        }).ToArray()),
        ["changed"] = Changed,
        ["favicon"] = Favicon is { } favicon ? new JsonObject {
            ["tabId"] = favicon.TabId.ToString("D"),
            ["adopts"] = favicon.Adopts
        } : null
    };

    #endregion
}
