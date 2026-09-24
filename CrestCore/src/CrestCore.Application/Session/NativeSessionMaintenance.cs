using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Checkpoint repair and retention operate on detached sessions. Native image
/// bytes never enter the session; the result identifies which live assets to
/// reattach, even when repair changed a colliding tab or Space identity.
public static class NativeSessionMaintenance {
    #region Variables

    /// What the Space made for an empty session is called and wears when the
    /// native caller supplies none.
    private const string BlankSpaceName = "Space 1";
    private const string BlankSpaceSymbol = "square.grid.2x2.fill";

    /// Where a repaired tab's native assets come from.
    internal sealed record TabOrigin(int SpaceIndex, int TabIndex, Guid SourceSpaceId, Guid SourceTabId);

    #endregion

    #region Actions - Session maintenance

    /// The repaired session and positional asset references: `{"session", "assets"}`.
    public static JsonObject Repair(JsonObject source, double now, JsonObject? emptySpace = null, IIdSource? ids = null) {
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedDate);
        var repaired = Repair(StoredSessionCodec.DecodeSession(source), StoredSessionCodec.Date(now),
            emptySpace is null ? null : StoredSessionCodec.DecodeSpace(emptySpace), ids ?? new SystemIdSource(), out var origins);
        return Answer(repaired, origins);
    }

    /// A repaired session with the positional references to the native assets
    /// each of its tabs keeps: `{"session", "assets"}`.
    internal static JsonObject Answer(SessionState repaired, IReadOnlyList<TabOrigin> origins) => new() {
        ["session"] = StoredSessionCodec.Encode(repaired),
        ["assets"] = new JsonArray(origins.Select(origin => (JsonNode?)new JsonObject {
            ["spaceIndex"] = origin.SpaceIndex,
            ["tabIndex"] = origin.TabIndex,
            ["sourceSpaceID"] = StoredSessionCodec.WrappedIdentity(origin.SourceSpaceId),
            ["sourceTabID"] = StoredSessionCodec.WrappedIdentity(origin.SourceTabId)
        }).ToArray())
    };

    /// Gives every Space, profile and tab its own identity, repairs folder trees,
    /// pin limits, split runs and split metadata, keeps a Space that is being
    /// deleted exactly as it was, and adds a Space when none would remain.
    internal static SessionState Repair(SessionState source, DateTimeOffset now, SpaceState? emptySpace, IIdSource ids,
        out IReadOnlyList<TabOrigin> origins) {
        var pending = source.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        var spaces = source.Spaces.ToList();
        if (spaces.Count == 0 || spaces.All(space => pending.Contains(space.Id)))
            spaces.Add((emptySpace ?? BlankSpace()) with {
                Id = ids.Next(),
                ProfileId = ids.Next(),
                Folders = [],
                Tabs = [StartTab(ids.Next(), now)],
                SplitGroups = [],
                ArchivedTabs = [],
                History = []
            });
        var spaceIds = new RuntimeIdentityRegistry(ids); var profiles = new RuntimeIdentityRegistry(ids);
        var tabIds = new RuntimeIdentityRegistry(ids); var assets = new List<TabOrigin>();
        var repaired = spaces.Select((space, spaceIndex) => {
            // Cleanup that is under way keeps the Space exactly as it was, and
            // its identities stay claimed so no other Space can take them.
            if (pending.Contains(space.Id)) {
                if (spaceIds.Claim(space.Id) != space.Id || profiles.Claim(space.ProfileId) != space.ProfileId)
                    throw new BrowserRuleException(BrowserRuleCodes.InvalidDeletionIntent);
                foreach (var (tab, tabIndex) in space.Tabs.Select((tab, index) => (tab, index))) {
                    _ = tabIds.Claim(tab.Id);
                    assets.Add(new(spaceIndex, tabIndex, space.Id, tab.Id));
                }
                foreach (var archived in space.ArchivedTabs.Where(archived => !IsStartPage(archived.Tab))) _ = tabIds.Claim(archived.Tab.Id);
                return space;
            }
            var identified = space with { Id = spaceIds.Claim(space.Id), ProfileId = profiles.Claim(space.ProfileId) };
            var folderIds = new RuntimeIdentityRegistry(ids);
            var folders = FolderTree.RepairPreorder(space.Folders.Select(folder => folder with { Id = folderIds.Claim(folder.Id) }).ToArray());
            var locations = folders.ToDictionary(folder => folder.Id, folder => folder.Location);
            var counts = new Dictionary<TabPlacement, int>();
            var tabs = space.Tabs.Select((tab, tabIndex) => {
                var id = tabIds.Claim(tab.Id);
                assets.Add(new(spaceIndex, tabIndex, space.Id, tab.Id));
                counts[tab.Placement] = counts.GetValueOrDefault(tab.Placement) + 1;
                var placement = tab.Placement.Holds(counts[tab.Placement]) ? tab.Placement : TabPlacement.Saved;
                var folder = placement.HoldsFolders && tab.FolderId is { } folderId
                    && locations.TryGetValue(folderId, out var location) && location == placement ? tab.FolderId : null;
                return Normalized(tab with {
                    Id = id,
                    Placement = placement,
                    SavedUrl = placement.IsDurable ? tab.SavedUrl ?? tab.Url : null,
                    FolderId = folder
                });
            }).ToList();
            if (tabs.Count == 0) tabs.Add(StartTab(tabIds.Claim(ids.Next()), now));
            var groups = SplitMembershipPolicy.Repair(tabs.Select(tab => new SplitMember(tab.SplitGroupId, tab.Placement, tab.FolderId)).ToArray());
            var archive = space.ArchivedTabs.Where(archived => !IsStartPage(archived.Tab)).Select(archived => archived with {
                Tab = Normalized(archived.Tab with {
                    Id = tabIds.Claim(archived.Tab.Id),
                    Placement = TabPlacement.Current,
                    SavedUrl = null,
                    FolderId = null,
                    SplitGroupId = null
                })
            });
            return identified with {
                Folders = folders,
                Tabs = tabs.Select((tab, index) => tab with { SplitGroupId = groups[index] }).ToArray(),
                ArchivedTabs = archive.ToArray(),
                History = space.History.Take(HistoryPolicy.MaximumEntries).ToArray(),
                SplitGroups = MergedSplitGroups(space.SplitGroups)
            };
        }).ToArray();
        origins = assets;
        // A launch Space that is gone falls back to the first Space that stays.
        var active = repaired.Select(space => space.Id).ToHashSet();
        var launch = source.DefaultSpaceId is { } chosen && active.Contains(chosen)
            ? chosen : repaired.First(space => !pending.Contains(space.Id)).Id;
        return source with { Spaces = repaired, DefaultSpaceId = launch };
    }

    /// Removes history and archive records older than each Space keeps them;
    /// a Space that is being deleted keeps everything. `{"session", "changed"}`.
    public static JsonObject Retain(JsonObject source, double now) {
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSavedDate);
        var session = StoredSessionCodec.DecodeSession(source);
        var pending = session.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        bool changed = false;
        var spaces = session.Spaces.Select(space => {
            if (pending.Contains(space.Id)) return space;
            var retention = space.Settings.BrowsingPreferences.DataRetention;
            var history = Retained(space.History, entry => entry.LastVisitedAt, Lifetime(retention.History), now);
            var archive = Retained(space.ArchivedTabs, archived => archived.ArchivedAt, Lifetime(retention.Archive), now);
            changed |= history.Count != space.History.Count || archive.Count != space.ArchivedTabs.Count;
            return space with { History = history, ArchivedTabs = archive };
        }).ToArray();
        return new() { ["session"] = StoredSessionCodec.Encode(session with { Spaces = spaces }), ["changed"] = changed };
    }

    private static IReadOnlyList<T> Retained<T>(IReadOnlyList<T> records, Func<T, DateTimeOffset> date, double? lifetime, double now) {
        if (lifetime is not { } seconds) return records;
        var expired = RecordRemovalPolicy.Expired(records.Select(record => StoredSessionCodec.Seconds(date(record))).ToArray(), now, seconds)
            .ToHashSet();
        return records.Where((_, index) => !expired.Contains(index)).ToArray();
    }

    private static double? Lifetime(DataRetention retention) => retention.Lifetime?.TotalSeconds;

    #endregion

    #region Actions - Records

    /// The Space an empty session starts with when the native caller supplies none.
    private static SpaceState BlankSpace() => new(Guid.Empty, Guid.Empty,
        new(BlankSpaceName, BlankSpaceSymbol, SpaceAccent.Indigo, null, StoredSessionCodec.DefaultBrowsingPreferences,
            StoredSessionCodec.DefaultCredentialPreferences, SpaceAccessPolicy.Open, true, null), [], [], [], [], []);

    private static bool IsStartPage(TabState tab) => tab.Url is null && tab.NativeContent is null;

    private static TabState StartTab(Guid id, DateTimeOffset now) => new(id, TabKind.StartPage.Name, null, null, null,
        TabKind.StartPage.Symbol, null, null, null, TabPlacement.Current, null, null, now, null, null, null, false);

    /// A blank rename is no rename, edit clocks are whole milliseconds, and a
    /// Start Page wears its own title and symbol.
    private static TabState Normalized(TabState tab) {
        var normalized = tab with {
            CustomTitle = string.IsNullOrWhiteSpace(tab.CustomTitle) ? null : tab.CustomTitle.Trim(),
            PositionModifiedAt = tab.PositionModifiedAt is { } position ? BrowserEditTimestamp.Normalize(position) : null,
            TitleModifiedAt = tab.TitleModifiedAt is { } title ? BrowserEditTimestamp.Normalize(title) : null
        };
        return IsStartPage(normalized)
            ? normalized with { Title = TabKind.StartPage.Name, Symbol = TabKind.StartPage.Symbol } : normalized;
    }

    /// One metadata record per split. Repeated records merge field by field, the
    /// later clock winning; the chosen icon stays opaque to the core.
    private static IReadOnlyList<SplitGroupState> MergedSplitGroups(IReadOnlyList<SplitGroupState> source) {
        var groups = new List<SplitGroupState>();
        foreach (var group in source) {
            var normalized = group with {
                CustomTitle = string.IsNullOrWhiteSpace(group.CustomTitle) ? null : group.CustomTitle.Trim(),
                TitleModifiedAt = Normalized(group.TitleModifiedAt),
                IconModifiedAt = Normalized(group.IconModifiedAt),
                TintModifiedAt = Normalized(group.TintModifiedAt)
            };
            int index = groups.FindIndex(candidate => candidate.Id == group.Id);
            if (index < 0) { groups.Add(normalized); continue; }
            var previous = groups[index];
            if (PreviousWins(previous.TitleModifiedAt, normalized.TitleModifiedAt))
                normalized = normalized with { CustomTitle = previous.CustomTitle, TitleModifiedAt = previous.TitleModifiedAt };
            if (PreviousWins(previous.IconModifiedAt, normalized.IconModifiedAt))
                normalized = normalized with { CustomIconSymbol = previous.CustomIconSymbol, IconModifiedAt = previous.IconModifiedAt };
            if (PreviousWins(previous.TintModifiedAt, normalized.TintModifiedAt))
                normalized = normalized with { Tint = previous.Tint, TintModifiedAt = previous.TintModifiedAt };
            groups[index] = normalized;
        }
        return groups;
    }

    private static DateTimeOffset? Normalized(DateTimeOffset? clock) => clock is { } value ? BrowserEditTimestamp.Normalize(value) : null;

    /// Whether an earlier record's field wins over a repeated record's.
    private static bool PreviousWins(DateTimeOffset? previous, DateTimeOffset? current) =>
        SyncConflictPolicy.Latest(current is { } value ? StoredSessionCodec.Seconds(value) : null,
            previous is { } earlier ? StoredSessionCodec.Seconds(earlier) : null) == 1;

    #endregion
}
