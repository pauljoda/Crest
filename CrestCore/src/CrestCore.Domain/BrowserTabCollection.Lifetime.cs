namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection
{
    public BrowserTab RestoreArchived(TabState source, DateTimeOffset now)
    {
        var tab = BrowserTab.Restore(source with
        {
            Placement = TabPlacement.Current, FolderId = null, SplitGroupId = null,
            LastActivatedAt = now, PositionModifiedAt = now
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
        var expired = tabs.Where(t => t.Placement == TabPlacement.Current && t.Kind != TabKind.StartPage
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
