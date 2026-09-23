using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using Key = CrestCore.Application.StoredSessionCodec.Key;

namespace CrestCore.Application;

/// <summary>A Space as the authority holds it: its settings as stored, and its
/// tabs, folders, split metadata, archive and history as typed records.</summary>
internal sealed record SpaceDocument(JsonObject Metadata, IReadOnlyList<TabState> Tabs, IReadOnlyList<FolderState> Folders,
    IReadOnlyList<SplitGroupState> SplitGroups, IReadOnlyList<ArchivedTabState> ArchivedTabs,
    IReadOnlyList<HistoryEntryState> History) {
    #region Variables

    internal Guid Id => StoredSessionCodec.Identity(Metadata[Key.Id]);
    internal Guid ProfileId => StoredSessionCodec.Identity(Metadata[Key.Profile]?[Key.Id]);

    #endregion

    #region Actions - Organization

    /// The Space's organization for one edit. Its archive starts empty and
    /// collects only the tabs the edit archives.
    internal BrowserTabCollection Organization() => BrowserTabCollection.Restore(Tabs, Folders, SplitGroups);

    /// The Space after an edit: its organization replaced and the edit's
    /// archived tabs added after the ones it already had.
    internal SpaceDocument Organized(BrowserTabCollection edited) => this with {
        Tabs = edited.TabStates,
        Folders = edited.Folders.ToArray(),
        SplitGroups = edited.SplitGroups.ToArray(),
        ArchivedTabs = [.. ArchivedTabs, .. edited.Archive]
    };

    /// Whether the two hold the same settings and records.
    internal bool Matches(SpaceDocument other) => JsonNode.DeepEquals(Metadata, other.Metadata)
        && Tabs.SequenceEqual(other.Tabs) && Folders.SequenceEqual(other.Folders)
        && SplitGroups.SequenceEqual(other.SplitGroups) && ArchivedTabs.SequenceEqual(other.ArchivedTabs)
        && History.SequenceEqual(other.History);

    #endregion
}
