namespace CrestCore.Domain;

/// Synchronous value edits used by native hosts that still own page lifetimes.
/// No engine calls or page creation take place while an edit is evaluated.
public sealed partial class BrowserTabCollection {
    public bool MoveTab(TabId id, TabPlacement placement, FolderId? requestedFolder, TabId? before,
        bool detachSplit, DateTimeOffset now) {
        var tab = Tab(id);
        if (before == id) throw new BrowserRuleException("invalid_tab_anchor");
        FolderId? folder = placement != TabPlacement.Pinned && folders.Any(f => f.Id == requestedFolder && f.Location == placement)
            ? requestedFolder : null;
        var remaining = tabs.Where(t => t.Id != id).ToList();
        if (placement == TabPlacement.Pinned && remaining.Count(t => t.Placement == TabPlacement.Pinned) >= 12)
            throw new BrowserRuleException("pinned_limit");
        bool Matches(BrowserTab t) => t.Placement == placement && t.FolderId == folder;
        int insertion = before is { } target ? remaining.FindIndex(t => t.Id == target && Matches(t)) : -1;
        if (insertion < 0) {
            int last = remaining.FindLastIndex(t => Matches(t));
            insertion = last >= 0 ? last + 1 : placement switch {
                TabPlacement.Pinned => remaining.FindIndex(t => t.Placement != TabPlacement.Pinned),
                TabPlacement.Saved => remaining.FindIndex(t => t.Placement == TabPlacement.Current),
                _ => remaining.Count
            };
            if (insertion < 0) insertion = remaining.Count;
        }
        if (tabs.IndexOf(tab) == insertion && tab.Placement == placement && tab.FolderId == folder
            && (!detachSplit || tab.SplitGroupId is null)) return false;
        var nextFolders = new FolderTree(folders).PreserveOrder([id], tabs);
        tab.Place(placement, folder, now, preservesSplit: !detachSplit);
        if (detachSplit) tab.SetSplit(null);
        tab.MarkPosition(now); remaining.Insert(insertion, tab);
        tabs.Clear(); tabs.AddRange(remaining); folders.Clear(); folders.AddRange(nextFolders);
        RepairSplitMembership();
        if (detachSplit) NormalizeSplits(now);
        return true;
    }

    public bool JoinSplitInPlace(TabId id, TabId targetId, int? memberIndex, Guid newGroup, DateTimeOffset now) {
        if (id == targetId) throw new BrowserRuleException("invalid_split");
        var tab = Tab(id); var target = Tab(targetId);
        if (target.Placement == TabPlacement.Pinned) throw new BrowserRuleException("invalid_split");
        var run = SplitMembers(targetId);
        var members = run.Where(t => t.Id != id).ToArray();
        if (members.Length >= MaximumSplitMembers) throw new BrowserRuleException("split_limit");
        int slot = Math.Clamp(memberIndex ?? members.Length, 0, members.Length);
        TabId? anchor = slot < members.Length ? members[slot].Id
            : tabs.Skip(tabs.IndexOf(run[^1]) + 1).FirstOrDefault(t => t.Id != id)?.Id;
        var group = target.SplitGroupId ?? newGroup;
        MoveTab(id, target.Placement, target.FolderId, anchor,
            tab.SplitGroupId is not null && tab.SplitGroupId != target.SplitGroupId, now);
        foreach (var member in members.Append(tab)) { member.SetSplit(group); member.MarkPosition(now); }
        NormalizeSplits(now);
        return true;
    }

    public bool MoveSplitMember(TabId id, int memberIndex, DateTimeOffset now) {
        var tab = Tab(id); var run = SplitMembers(id);
        if (run.Count < 2) return false;
        int first = tabs.IndexOf(run[0]); int insertion = first + Math.Clamp(memberIndex, 0, run.Count - 1);
        if (tabs.IndexOf(tab) == insertion) return false;
        var originalPositions = run.ToDictionary(t => t.Id, tabs.IndexOf);
        tabs.Remove(tab); tabs.Insert(insertion, tab);
        foreach (var member in run)
            if (tabs.IndexOf(member) != originalPositions[member.Id]) member.MarkPosition(now);
        return true;
    }

    public void InsertTab(BrowserTab tab, int? requestedIndex, bool duplicate = false) {
        if (tab.Placement == TabPlacement.Pinned && tabs.Count(t => t.Placement == TabPlacement.Pinned) >= 12)
            throw new BrowserRuleException("pinned_limit");
        if (tabs.Count >= MaximumTabs) throw new BrowserRuleException("tab_limit");
        if (tabs.Any(t => t.Id == tab.Id)) throw new BrowserRuleException("duplicate_tab");
        int First(Func<BrowserTab, bool> predicate) { int i = tabs.FindIndex(t => predicate(t)); return i < 0 ? tabs.Count : i; }
        int lower = tab.Placement switch {
            TabPlacement.Pinned => 0,
            TabPlacement.Saved => Math.Min(First(t => t.Placement == TabPlacement.Saved), First(t => t.Placement == TabPlacement.Current)),
            _ => First(t => t.Placement == TabPlacement.Current)
        };
        int upper = tab.Placement switch {
            TabPlacement.Pinned => First(t => t.Placement != TabPlacement.Pinned),
            TabPlacement.Saved => First(t => t.Placement == TabPlacement.Current),
            _ => tabs.Count
        };
        int insertion = requestedIndex is { } requested ? Math.Clamp(requested, lower, upper)
            : duplicate || tab.Placement == TabPlacement.Current ? lower : upper;
        tabs.Insert(insertion, tab);
    }

    public TabId? DismissTabs(IReadOnlyCollection<TabId> requested, TabId? selected, TabId? fallback,
        DateTimeOffset now, bool deleting, bool ensureSelection, bool resetArchivePlacement) {
        var removing = requested.ToHashSet();
        var removed = tabs.Where(t => removing.Contains(t.Id)).ToArray();
        if (removed.Length != removing.Count || !deleting && removed.Any(t => t.Placement != TabPlacement.Current))
            throw new BrowserRuleException("unknown_current_tab");
        var orderedFolders = new FolderTree(folders).PreserveOrder(removing, tabs);
        foreach (var tab in removed.Where(t => !t.Content.IsStartPage)) {
            var value = tab.Capture() with { SplitGroupId = null };
            if (resetArchivePlacement) value = value with { Placement = TabPlacement.Current, FolderId = null, SavedUrl = null };
            archive.Add(new(value, now, deleting ? "deleted" : "closed"));
        }
        tabs.RemoveAll(t => removing.Contains(t.Id));
        folders.Clear(); folders.AddRange(orderedFolders);
        if (selected is { } current && removing.Contains(current))
            selected = fallback is { } candidate && tabs.Any(t => t.Id == candidate) ? candidate : null;
        if (ensureSelection && (selected is null || !tabs.Any(t => t.Id == selected)))
            selected = tabs.FirstOrDefault(t => t.Placement == TabPlacement.Current)?.Id
                ?? tabs.FirstOrDefault(t => t.Placement == TabPlacement.Pinned)?.Id
                ?? tabs.FirstOrDefault(t => t.Placement == TabPlacement.Saved)?.Id;
        NormalizeSplits(now);
        return selected;
    }
}
