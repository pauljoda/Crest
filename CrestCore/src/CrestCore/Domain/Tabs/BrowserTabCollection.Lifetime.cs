using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Lifetime

    /// Archives a Quick Window's page as the closed open tab `closed`.
    /// Refused with `TabAlreadyExists` when the Space holds its identity.
    public void ArchiveTransient(TabState closed, DateTimeOffset now) {
        if (tabs.Any(t => t.Id == closed.Id) || archive.Any(archived => archived.Tab.Id == closed.Id))
            throw new Rejected(new TabAlreadyExists(closed.Id));
        archive.Add(new(closed, now, ArchiveReason.QuickWindow));
    }

    public BrowserTab RestoreArchived(TabState source, DateTimeOffset now) {
        var tab = BrowserTab.Restore(source with {
            Placement = TabPlacement.Current,
            FolderId = null,
            SplitGroupId = null,
            LastActivatedAt = now,
            PositionModifiedAt = BrowserEditTimestamp.Normalize(now)
        });
        InsertTab(tab, null);
        return tab;
    }

    /// Opens again `returning`, open tabs a clear archived from this Space as
    /// it stood `before`: each after the latest tab that came before it there
    /// and is here now, or first among the open tabs, in the folder and split
    /// it sat in while they can hold it. A folder or split the clear took goes
    /// back as it stood, after the folder it followed there. Each tab keeps
    /// its record, its place marked as moved `now`.
    public void RestoreCleared(SpaceState before, IReadOnlyList<TabState> returning, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(before);
        ArgumentNullException.ThrowIfNull(returning);
        RestoreFolders(before.Folders, returning);
        var states = returning.ToDictionary(tab => tab.Id);
        for (int index = 0; index < before.Tabs.Count; index++) {
            if (!states.TryGetValue(before.Tabs[index].Id, out var state)) continue;
            var folder = state.FolderId is { } id && folders.Any(kept => kept.Id == id && kept.Location == state.Placement) ? id : (Guid?)null;
            var tab = BrowserTab.Restore(state with { FolderId = folder, PositionModifiedAt = BrowserEditTimestamp.Normalize(now) });
            var previous = before.Tabs.Take(index).LastOrDefault(earlier => tabs.Any(held => held.Id == earlier.Id));
            InsertTab(tab, previous is null ? null : tabs.FindIndex(held => held.Id == previous.Id) + 1);
        }
        splitGroups.AddRange(before.SplitGroups.Where(group => returning.Any(tab => tab.SplitGroupId == group.Id)
            && splitGroups.All(kept => kept.Id != group.Id)));
        NormalizeSplits(now);
        PruneSplitMetadata();
    }

    /// Puts a saved or pinned tab's page away, returning the tab to its saved
    /// address when `returnToSavedUrl`, and answers the tab its window shows
    /// next: `fallback` in place of the tab when it showed it.
    public Guid? CloseDurable(Guid id, Guid? selected, Guid? fallback, bool returnToSavedUrl) {
        var tab = Tab(id);
        if (returnToSavedUrl) tab.ReturnToSavedUrl();
        return selected == id ? fallback is { } other && other != id && tabs.Any(t => t.Id == other)
            ? other : null : selected;
    }

    /// Archives open tabs unused for longer than `lifetime`. The tab the caller
    /// shows and any tab in `kept` (tabs other windows show) survive.
    public Guid? CleanupCurrentTabs(Guid? selected, TimeSpan lifetime, DateTimeOffset now,
        IReadOnlyCollection<Guid>? kept = null) {
        var expired = tabs.Where(t => !t.Placement.IsDurable && !t.Content.IsStartPage
            && t.Id != selected && kept?.Contains(t.Id) != true && now - t.LastActivatedAt > lifetime).ToArray();
        var ids = expired.Select(t => t.Id).ToHashSet();
        var nextFolders = new FolderTree(folders).PreserveOrder(ids, tabs);
        foreach (var tab in expired)
            archive.Add(new(tab.State with { SplitGroupId = null }, now, ArchiveReason.AutoCleanup));
        tabs.RemoveAll(t => ids.Contains(t.Id));
        folders.Clear(); folders.AddRange(nextFolders);
        // Maintenance preserves an empty selection and does not dissolve a
        // surviving split. User-driven dismissal has a different contract.
        if (selected is not null && !tabs.Any(t => t.Id == selected))
            selected = FallbackSelection();
        return selected;
    }

    /// Puts back the folders of `before` that the tabs `returning` sat in,
    /// and the folders above them, that this Space no longer holds: each as it
    /// stood, after the folder it followed there, at the top level once the
    /// folder it sat in is gone or lies in another section.
    private void RestoreFolders(IReadOnlyList<FolderState> before, IReadOnlyList<TabState> returning) {
        var parents = before.ToDictionary(folder => folder.Id, folder => folder.ParentId);
        HashSet<Guid> wanted = [];
        foreach (var tab in returning)
            for (var id = tab.FolderId; id is { } folder && parents.ContainsKey(folder) && wanted.Add(folder); id = parents[folder]) { }
        for (int index = 0; index < before.Count; index++) {
            var folder = before[index];
            if (!wanted.Contains(folder.Id) || folders.Any(kept => kept.Id == folder.Id)) continue;
            var previous = before.Take(index).LastOrDefault(earlier => folders.Any(kept => kept.Id == earlier.Id));
            folders.Insert(previous is null ? 0 : folders.FindIndex(kept => kept.Id == previous.Id) + 1, folder);
        }
        for (int index = 0; index < folders.Count; index++) {
            if (folders[index].ParentId is not { } parent || !wanted.Contains(folders[index].Id)) continue;
            if (folders.FirstOrDefault(kept => kept.Id == parent) is not { } holder || holder.Location != folders[index].Location)
                folders[index] = folders[index] with { ParentId = null };
        }
        new FolderTree(folders).Validate();
    }

    #endregion
}
