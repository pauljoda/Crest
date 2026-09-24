using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Lifetime

    public BrowserTab PromoteTransient(TabState source, Guid? selected, DateTimeOffset now) {
        var tab = BrowserTab.Restore(TransientState(source, now));
        int? insertion = null;
        if (selected is { } id && tabs.FindIndex(t => t.Id == id) is var index && index >= 0) {
            var split = tabs[index].SplitGroupId;
            index++;
            while (split is not null && index < tabs.Count && tabs[index].SplitGroupId == split) index++;
            insertion = index;
        }
        InsertTab(tab, insertion);
        return tab;
    }

    public void ArchiveTransient(TabState source, DateTimeOffset now) {
        if (tabs.Any(t => t.Id == source.Id) || archive.Any(archived => archived.Tab.Id == source.Id))
            throw new BrowserRuleException(BrowserRuleCodes.DuplicateTab);
        archive.Add(new(TransientState(source, now), now, ArchiveReason.QuickWindow));
    }

    private static TabState TransientState(TabState source, DateTimeOffset now) {
        if (!TabContent.FromStored(source.NativeContent?.Kind, source.Url, source.Title).IsWebPage || string.IsNullOrEmpty(source.Url))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidTransientPage);
        return source with {
            Placement = TabPlacement.Current,
            FolderId = null,
            SplitGroupId = null,
            SavedUrl = null,
            LastActivatedAt = now
        };
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

    public Guid? CloseDurable(Guid id, Guid? selected, Guid? fallback, bool returnToSavedUrl) {
        var tab = Tab(id);
        if (!tab.Placement.IsDurable) throw new BrowserRuleException(BrowserRuleCodes.NotDurableTab);
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

    #endregion
}
