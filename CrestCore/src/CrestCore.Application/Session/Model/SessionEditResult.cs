using System.Text;
using System.Text.Json.Nodes;

namespace CrestCore.Application;

internal sealed record SessionTabCopy(Guid Source, Guid Copy);

internal sealed record SessionFaviconUpdate(Guid TabId, bool Adopts);

/// <summary>The edited Space and native side effects returned by one session edit.</summary>
internal sealed record SessionEditResult(JsonNode Space, Guid? TabId, bool SelectSpace,
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
            value["selectSpace"]!.GetValue<bool>(), copies, value["changed"]!.GetValue<bool>(), favicon);
    }

    #endregion

    #region Actions - Encoding

    public byte[] Encode() => Encoding.UTF8.GetBytes(new JsonObject {
        ["space"] = Space.DeepClone(),
        ["tabId"] = TabId?.ToString("D"),
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
    }.ToJsonString());

    #endregion
}
