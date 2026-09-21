namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection
{
    public BrowserTab PromoteTransient(TabState source, TabId? selected, DateTimeOffset now)
    {
        var tab = BrowserTab.Restore(TransientState(source, now));
        int? insertion = null;
        if (selected is { } id && tabs.FindIndex(t => t.Id == id) is var index && index >= 0)
        {
            var split = tabs[index].SplitGroupId;
            index++;
            while (split is not null && index < tabs.Count && tabs[index].SplitGroupId == split) index++;
            insertion = index;
        }
        InsertTab(tab, insertion);
        return tab;
    }

    public void ArchiveTransient(TabState source, DateTimeOffset now)
    {
        if (tabs.Any(t => t.Id == source.Id) || archive.Any(t => t.Id == source.Id))
            throw new BrowserRuleException("duplicate_tab");
        archive.Add(new(TransientState(source, now), now, "quickWindow"));
    }

    private static TabState TransientState(TabState source, DateTimeOffset now)
    {
        if (!source.Content.IsWebPage || string.IsNullOrEmpty(source.Url))
            throw new BrowserRuleException("invalid_transient_page");
        return source with { Placement = TabPlacement.Current, FolderId = null, SplitGroupId = null,
            SavedUrl = null, LastActivatedAt = now };
    }

    public BrowserTab RestoreArchived(TabState source, DateTimeOffset now)
    {
        var tab = BrowserTab.Restore(source with
        {
            Placement = TabPlacement.Current, FolderId = null, SplitGroupId = null,
            LastActivatedAt = now, PositionModifiedAt = BrowserEditTimestamp.Normalize(now)
        });
        InsertTab(tab, null);
        return tab;
    }

    public TabId? CloseDurable(TabId id, TabId? selected, TabId? fallback, bool returnToSavedUrl)
    {
        var tab = Tab(id);
        if (tab.Placement == TabPlacement.Current) throw new BrowserRuleException("not_durable_tab");
        tab.Unload(returnToSavedUrl);
        return selected == id ? fallback is { } other && other != id && tabs.Any(t => t.Id == other)
            ? other : null : selected;
    }

    public TabId? CleanupCurrentTabs(TabId? selected, TimeSpan lifetime, DateTimeOffset now)
    {
        var expired = tabs.Where(t => t.Placement == TabPlacement.Current && !t.Content.IsStartPage
            && t.Id != selected && now - t.LastActivatedAt > lifetime).ToArray();
        var ids = expired.Select(t => t.Id).ToHashSet();
        var nextFolders = new FolderTree(folders).PreserveOrder(ids, tabs);
        foreach (var tab in expired)
            archive.Add(new(tab.Capture() with { SplitGroupId = null }, now, "autoCleanup"));
        tabs.RemoveAll(t => ids.Contains(t.Id));
        folders.Clear(); folders.AddRange(nextFolders);
        // Maintenance preserves an empty selection and does not dissolve a
        // surviving split. User-driven dismissal has a different contract.
        if (selected is not null && !tabs.Any(t => t.Id == selected))
            selected = tabs.FirstOrDefault(t => t.Placement == TabPlacement.Current)?.Id
                ?? tabs.FirstOrDefault(t => t.Placement == TabPlacement.Pinned)?.Id
                ?? tabs.FirstOrDefault(t => t.Placement == TabPlacement.Saved)?.Id;
        return selected;
    }
}
