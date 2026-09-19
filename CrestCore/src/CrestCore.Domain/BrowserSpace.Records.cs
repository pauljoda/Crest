namespace CrestCore.Domain;

public sealed partial class BrowserSpace
{
    public bool UpdateHistoryTitle(BrowserTab tab)
    {
        if (tab.IsLoading || tab.Failure is not null || tab.Url is null) return false;
        var index = history.FindIndex(h => h.Url == tab.Url.Split('#')[0]);
        if (index < 0 || history[index].Title == tab.Title) return false;
        history[index] = history[index] with { Title = tab.Title }; return true;
    }
    public HistoryVisit HistoryEntry(Guid id)
    { EnsureAccessible(); return history.Find(h => h.Id == id) ?? throw new BrowserRuleException("unknown_history_entry"); }
    public void DeleteHistoryEntry(Guid id)
    {
        var entry = HistoryEntry(id); history.Remove(entry);
    }
    public void ClearHistory() { EnsureAccessible(); history.Clear(); }
    public void DeleteArchivedTab(TabId id)
    {
        EnsureAccessible();
        if (archive.RemoveAll(a => a.Id == id) == 0) throw new BrowserRuleException("unknown_archive");
    }
    public void ClearArchive() { EnsureAccessible(); archive.Clear(); }
}

public sealed partial class BrowserWorkspace
{
    public BrowserTab OpenRecords(WindowId windowId, SpaceId spaceId, string kind)
    {
        if (kind is not ("history" or "archive")) throw new BrowserRuleException("invalid_native_kind");
        var window = Window(windowId); var space = Space(spaceId); space.EnsureAccessible();
        if (space.Tabs.FirstOrDefault(t => t.NativeKind == kind) is { } existing) return existing;
        var state = new TabState(new(ids.Next()), TabKind.Native, null, kind == "history" ? "History" : "Archive",
            TabPlacement.Current, null, null, null, clock.Now, null, null, false, null, kind);
        var tab = BrowserTab.Restore(state); space.AddOpenedTab(tab, window.Selection(spaceId)); return tab;
    }
}
