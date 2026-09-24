using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal sealed record SessionTabCopy(Guid Source, Guid Copy) {
    #region Actions - Publishing

    public TabCopied Copied(Guid workspaceId) => new(workspaceId, Source, Copy);

    #endregion
}

internal sealed record SessionFaviconUpdate(Guid TabId, bool Adopts) {
    #region Actions - Publishing

    public TabFaviconAssigned Assigned(Guid workspaceId) => new(workspaceId, TabId, Adopts);

    #endregion
}

/// The tabs a command copied and the image it assigned, which comparing the
/// sessions before and after it cannot tell.
internal sealed record SessionTabEvents(IReadOnlyList<SessionTabCopy> Copies, SessionFaviconUpdate? Favicon) {
    #region Variables

    public static SessionTabEvents None { get; } = new([], null);

    #endregion

    #region Actions - Publishing

    /// The changes that tell a reader of `workspaceId` what happened.
    public IEnumerable<Change> Changes(Guid workspaceId) =>
        Copies.Select(copy => (Change)copy.Copied(workspaceId)).Concat(Favicon is { } favicon ? [favicon.Assigned(workspaceId)] : []);

    #endregion
}

/// <summary>The Space organization and native side effects one session edit produced.
/// <paramref name="SelectedTabId"/> is the tab the requesting window shows in the
/// edited Space afterwards and <paramref name="SelectSpace"/> whether it switches to
/// that Space; the device applies both to that window when the edit commits.</summary>
internal sealed record SessionEditResult(BrowserTabCollection Edited, Guid? TabId, Guid? SelectedTabId, bool SelectSpace,
    IReadOnlyList<SessionTabCopy> Copies, bool Changed, SessionFaviconUpdate? Favicon) {
    #region Variables

    /// What the edit did that its sessions cannot tell.
    public SessionTabEvents Events => new(Copies, Favicon);

    #endregion

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
