namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection
{
    /// Moves ownership without closing, archiving, or creating a replacement tab.
    /// All destination checks precede mutation of either collection.
    public TabId? TransferTo(BrowserTabCollection destination, TabId id, TabId? selected, TabId? fallback,
        TabPlacement? requestedPlacement, FolderId? requestedFolder, TabId? before,
        bool afterSelection, TabId? destinationSelection, DateTimeOffset now)
    {
        if (ReferenceEquals(this, destination)) throw new BrowserRuleException("same_collection_transfer");
        var tab = Tab(id);
        if (destination.tabs.Any(t => t.Id == id) || destination.archive.Any(t => t.Id == id))
            throw new BrowserRuleException("duplicate_tab");
        if (destination.tabs.Count >= MaximumTabs) throw new BrowserRuleException("tab_limit");
        var placement = requestedPlacement ?? tab.Placement;
        FolderId? folder = placement != TabPlacement.Pinned && destination.folders.Any(f => f.Id == requestedFolder && f.Location == placement)
            ? requestedFolder : null;
        if (placement == TabPlacement.Pinned && destination.tabs.Count(t => t.Placement == placement) >= 12)
            throw new BrowserRuleException("pinned_limit");
        if (before == id) throw new BrowserRuleException("invalid_tab_anchor");
        bool Matches(BrowserTab t) => t.Placement == placement && t.FolderId == folder;
        int insertion = before is { } anchor ? destination.tabs.FindIndex(t => t.Id == anchor && Matches(t)) : -1;
        if (insertion < 0)
        {
            int last = destination.tabs.FindLastIndex(Matches);
            insertion = last >= 0 ? last + 1 : placement switch
            {
                TabPlacement.Pinned => destination.tabs.FindIndex(t => t.Placement != TabPlacement.Pinned),
                TabPlacement.Saved => destination.tabs.FindIndex(t => t.Placement == TabPlacement.Current),
                _ => destination.tabs.Count
            };
            if (insertion < 0) insertion = destination.tabs.Count;
        }
        if (afterSelection && destination.tabs.FindIndex(t => t.Id == destinationSelection) is var origin && origin >= 0)
        {
            insertion = origin + 1;
            if (destination.tabs[origin].SplitGroupId is { } group)
                while (insertion < destination.tabs.Count && destination.tabs[insertion].SplitGroupId == group) insertion++;
        }
        var ordered = new FolderTree(folders).PreserveOrder([id], tabs);
        tabs.Remove(tab); folders.Clear(); folders.AddRange(ordered);
        tab.Place(placement, folder, now); tab.SetSplit(null); tab.MarkPosition(now);
        destination.tabs.Insert(insertion, tab);
        // Cross-Space organization retains a singleton's stored membership,
        // as checkpoint repair does for incomplete sync batches. A window
        // transfer explicitly detaches and normalizes its source run.
        if (afterSelection) NormalizeSplits(now); else RepairSplitMembership();
        destination.RepairSplitMembership();
        return selected == id ? fallback is { } next && tabs.Any(t => t.Id == next) ? next : null : selected;
    }
}
