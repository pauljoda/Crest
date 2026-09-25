using CrestCore.Contracts;

namespace CrestCore.Application;

/// The changes that take a workspace's session from one accepted state to the
/// next, derived by comparing the two states, so no handler lists what it
/// changed and none can forget a change. A state that did not change publishes
/// nothing, and a Space, a list or a record the commit kept publishes nothing
/// for it; a kept one is usually the same object, which is checked first.
///
/// Every change is idempotent: a reader that applies a batch twice holds the
/// same state as one that applies it once. The Spaces arrive first, then each
/// Space's own changes in session order, with the lists its sidebar shows
/// differently after its records, then the workspace's own members.
internal static class SessionChanges {
    #region Types

    /// One list's changes: the rows that are new or changed, the identities of
    /// the rows that are gone, and the whole new order when the rows' own
    /// placement does not reproduce it.
    private sealed record Rows<T>(IReadOnlyList<T> Updated, IReadOnlyList<Guid> Removed, IReadOnlyList<Guid>? Order);

    #endregion

    #region Actions - Publishing

    /// The changes from `previous` to `next`, none when they hold the same state.
    public static IReadOnlyList<Change> Publish(Guid workspaceId, SessionState previous, SessionState next) {
        ArgumentNullException.ThrowIfNull(previous);
        ArgumentNullException.ThrowIfNull(next);
        if (ReferenceEquals(previous, next)) return [];
        var changes = new List<Change>();
        var spaceChanges = new List<Change>();
        var before = previous.Spaces.ToDictionary(space => space.Id);
        var resent = new HashSet<Guid>();
        foreach (var space in next.Spaces) {
            if (!before.TryGetValue(space.Id, out var old) || ReferenceEquals(old, space)) continue;
            // A Space whose profile changed, or whose changed records cannot be
            // told apart by identity, arrives again whole.
            if (old.ProfileId == space.ProfileId && SpaceChanged(workspaceId, old, space) is { } changed) spaceChanges.AddRange(changed);
            else resent.Add(space.Id);
        }
        var retained = next.Spaces.Select(space => space.Id).Where(id => before.ContainsKey(id) && !resent.Contains(id)).ToHashSet();
        var added = next.Spaces.Where(space => !retained.Contains(space.Id)).ToArray();
        var removed = previous.Spaces.Select(space => space.Id).Where(id => !retained.Contains(id)).ToArray();
        var order = next.Spaces.Select(space => space.Id).ToArray();
        var placed = previous.Spaces.Select(space => space.Id).Where(retained.Contains).Concat(added.Select(space => space.Id));
        if (added.Length > 0 || removed.Length > 0 || !placed.SequenceEqual(order))
            changes.Add(new SpacesChanged(workspaceId, added, removed, placed.SequenceEqual(order) ? null : order));
        changes.AddRange(spaceChanges);
        if (previous.DefaultSpaceId != next.DefaultSpaceId
            || previous.DisposableSeedMarker is null != next.DisposableSeedMarker is null
            || !previous.SpaceDeletions.SequenceEqual(next.SpaceDeletions))
            changes.Add(new WorkspaceChanged(workspaceId, next.DefaultSpaceId, next.DisposableSeedMarker is not null, next.SpaceDeletions));
        if (!ReferenceEquals(previous.AppPreferences, next.AppPreferences) && previous.AppPreferences != next.AppPreferences)
            changes.Add(new AppPreferencesChanged(workspaceId, next.AppPreferences));
        return changes;
    }

    /// One retained Space's changes, settings first and then each record list,
    /// or null when a changed list holds two records with one identity. The
    /// core gives every record its own identity; only a Space an older release
    /// stored, kept exactly as it was while it is deleted, may share one.
    private static List<Change>? SpaceChanged(Guid workspaceId, SpaceState old, SpaceState space) {
        var changes = new List<Change>();
        if (!ReferenceEquals(old.Settings, space.Settings) && old.Settings != space.Settings)
            changes.Add(new SpaceSettingsChanged(workspaceId, space.Id, space.Settings));
        if (!TryChange(old.Folders, space.Folders, folder => folder.Id, recordedFirst: false, out var folders)) return null;
        if (folders is not null) changes.Add(new FoldersChanged(workspaceId, space.Id, folders.Updated, folders.Removed, folders.Order));
        if (!TryChange(old.Tabs, space.Tabs, tab => tab.Id, recordedFirst: false, out var tabs)) return null;
        if (tabs is not null) changes.Add(new TabsChanged(workspaceId, space.Id, tabs.Updated, tabs.Removed, tabs.Order));
        if (!ReferenceEquals(old.SplitGroups, space.SplitGroups) && !old.SplitGroups.SequenceEqual(space.SplitGroups))
            changes.Add(new SplitGroupsChanged(workspaceId, space.Id, space.SplitGroups));
        if (ChangedSidebar(workspaceId, old, space) is { } sidebar) changes.Add(sidebar);
        if (!TryChange(old.ArchivedTabs, space.ArchivedTabs, archived => archived.Tab.Id, recordedFirst: false, out var archive))
            return null;
        if (archive is not null) changes.Add(new ArchiveChanged(workspaceId, space.Id, archive.Updated, archive.Removed, archive.Order));
        if (!TryChange(old.History, space.History, entry => entry.Id, recordedFirst: true, out var history)) return null;
        if (history is not null) changes.Add(new HistoryChanged(workspaceId, space.Id, history.Updated, history.Removed, history.Order));
        return changes;
    }

    /// The lists of a retained Space's sidebar that its edit changed, or null when it
    /// lists what it listed. Only an edit to what the sidebar reads of its tabs and
    /// folders builds the outline; a new title, address or icon never does.
    private static SidebarChanged? ChangedSidebar(Guid workspaceId, SpaceState old, SpaceState space) {
        if (SidebarOutline.ListsAlike(old.Tabs, space.Tabs, old.Folders, space.Folders)) return null;
        var (lists, removed) = space.Sidebar.Since(old.Sidebar);
        return lists.Count == 0 && removed.Count == 0 ? null : new(workspaceId, space.Id, lists, removed);
    }

    /// A list's changes, null when it holds the same rows; false when two of
    /// its rows share an identity. A new or changed row stays where it stands
    /// or goes after the others, or, when `recordedFirst`, the new and changed
    /// rows go before every other in their own order, as a newest-first
    /// history records a visit.
    private static bool TryChange<T>(IReadOnlyList<T> before, IReadOnlyList<T> after, Func<T, Guid> identity, bool recordedFirst,
        out Rows<T>? rows) where T : class {
        rows = null;
        if (ReferenceEquals(before, after) || before.SequenceEqual(after)) return true;
        var old = new Dictionary<Guid, T>(before.Count);
        if (!before.All(row => old.TryAdd(identity(row), row))) return false;
        var order = after.Select(identity).ToArray();
        var present = order.ToHashSet();
        if (present.Count != order.Length) return false;
        var removed = before.Select(identity).Where(id => !present.Contains(id)).ToArray();
        var updated = after.Where(row => !old.TryGetValue(identity(row), out var was) || !Equals(was, row)).ToArray();
        var moved = updated.Select(identity).ToHashSet();
        var placed = recordedFirst
            ? updated.Select(identity).Concat(before.Select(identity).Where(id => present.Contains(id) && !moved.Contains(id)))
            : before.Select(identity).Where(present.Contains).Concat(updated.Select(identity).Where(id => !old.ContainsKey(id)));
        rows = new(updated, removed, placed.SequenceEqual(order) ? null : order);
        return true;
    }

    #endregion
}
