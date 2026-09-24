using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal sealed record SessionTabCopy(Guid Source, Guid Copy);

internal sealed record SessionFaviconUpdate(Guid TabId, bool Adopts);

/// <summary>The Space organization and native side effects one session edit produced.
/// <paramref name="SelectedTabId"/> is the tab the requesting window shows in the
/// edited Space afterwards and <paramref name="SelectSpace"/> whether it switches to
/// that Space; the device applies both to that window when the edit commits.</summary>
internal sealed record SessionEditResult(BrowserTabCollection Edited, Guid? TabId, Guid? SelectedTabId, bool SelectSpace,
    IReadOnlyList<SessionTabCopy> Copies, bool Changed, SessionFaviconUpdate? Favicon) {
    #region Actions - Encoding

    /// The command answer the native caller reads: the edited Space with the tabs
    /// this edit archived and no history, and its side effects.
    public JsonObject Answer(SpaceState edited) => new() {
        ["space"] = StoredSessionCodec.Encode(edited with { History = [], ArchivedTabs = Edited.Archive }),
        ["tabId"] = TabId?.ToString("D"),
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
