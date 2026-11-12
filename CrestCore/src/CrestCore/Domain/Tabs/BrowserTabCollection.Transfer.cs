using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Transfer

    /// Moves ownership without closing, archiving, or creating a replacement tab.
    /// All destination checks precede mutation of either collection. Refused with
    /// `TabAlreadyExists` when the destination holds the tab or keeps it in its
    /// archive, `TabLimitReached` or `PinnedTabsFull` when it has no room,
    /// `UnknownFolder` for a folder the destination does not hold, and
    /// `InvalidFolderPlacement` for one outside the section or a tab named to
    /// go before itself.
    public Guid? TransferTo(BrowserTabCollection destination, Guid id, Guid? selected, Guid? fallback,
        TabPlacement? requestedPlacement, Guid? requestedFolder, Guid? before,
        bool afterSelection, Guid? destinationSelection, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(destination);
        if (ReferenceEquals(this, destination)) throw new ArgumentException("A tab moves to another Space.", nameof(destination));
        var tab = Tab(id);
        if (destination.tabs.Any(t => t.Id == id) || destination.archive.Any(archived => archived.Tab.Id == id))
            throw new Rejected(new TabAlreadyExists(id));
        if (destination.tabs.Count >= MaximumTabs) throw new Rejected(new TabLimitReached(MaximumTabs));
        var placement = requestedPlacement ?? tab.Placement;
        // A folder the move names must be there, in the section it moves to.
        if (requestedFolder is { } named && (destination.KnownFolder(named).Location != placement || !placement.HoldsFolders))
            throw new Rejected(new InvalidFolderPlacement());
        Guid? folder = requestedFolder;
        RequireRoom(placement, destination.tabs.Count(t => t.Placement == placement) + 1);
        if (before == id) throw new Rejected(new InvalidFolderPlacement());
        bool Matches(BrowserTab tab) => tab.Placement == placement && tab.FolderId == folder;
        int insertion = before is { } anchor ? destination.tabs.FindIndex(t => t.Id == anchor && Matches(t)) : -1;
        if (insertion < 0) {
            int last = destination.tabs.FindLastIndex(Matches);
            insertion = last >= 0 ? last + 1 : NextSection(destination.tabs, placement);
        }
        if (afterSelection && destination.tabs.FindIndex(t => t.Id == destinationSelection) is var origin && origin >= 0) {
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

    /// Moves the folder `id`, with every folder and tab inside it however
    /// deep, into `destination`, another Space's organization, at the top
    /// level of its section there, after what that section holds. Each folder
    /// is made anew there under an identity from `ids`, keeping its title,
    /// look, disclosure and place in the tree; each tab keeps its identity, its
    /// state and its split, whose name, icon, tint and collapse go with it,
    /// under an identity from `ids` for a split whose own the destination
    /// already uses.
    /// Answers the tab the window shows here next, `fallback` in place of
    /// `shown` when it moved, and the tabs that moved, in order. All
    /// destination checks precede mutation of either collection. Refused with
    /// `UnknownFolder` for a folder this Space does not hold,
    /// `TabAlreadyExists` when the destination holds one of its tabs, open or
    /// in its archive, and
    /// `TabLimitReached`, `PinnedTabsFull` or `FolderLimitReached` when the
    /// destination has no room.
    public (Guid? Shown, IReadOnlyList<Guid> Moved) TransferFolderTo(BrowserTabCollection destination, Guid id, Guid? shown,
        Guid? fallback, IIdSource ids, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(destination);
        ArgumentNullException.ThrowIfNull(ids);
        if (ReferenceEquals(this, destination)) throw new ArgumentException("A folder moves to another Space.", nameof(destination));
        var tree = new FolderTree(folders);
        var placement = KnownFolder(id).Location;
        var moving = tree.Subtree(id);
        var moved = TabsInFolder(id);
        var movedIds = moved.ToHashSet();
        var held = destination.tabs.Select(tab => tab.Id)
            .Concat(destination.archive.Select(archived => archived.Tab.Id)).ToHashSet();
        foreach (var tabId in moved)
            if (held.Contains(tabId)) throw new Rejected(new TabAlreadyExists(tabId));
        if (destination.tabs.Count + moved.Count > MaximumTabs) throw new Rejected(new TabLimitReached(MaximumTabs));
        RequireRoom(placement, destination.tabs.Count(tab => tab.Placement == placement) + moved.Count);
        if (destination.folders.Count + moving.Count > FolderTree.MaximumCount)
            throw new Rejected(new FolderLimitReached(FolderTree.MaximumCount));
        // The folders keep their tree under new identities: the top one at the
        // top level, after the section's rows, and an empty one inside it
        // before the moved tab it anchors to, or else last.
        FolderState[] subtree = [.. tree.DisplayOrder().Where(folder => moving.Contains(folder.Id))];
        var copies = subtree.ToDictionary(folder => folder.Id, _ => ids.Next());
        FolderState[] made = [.. subtree.Select(folder => folder with {
            Id = copies[folder.Id],
            ParentId = folder.ParentId is { } parent && copies.TryGetValue(parent, out var copy) ? copy : null,
            OrderAnchorTabId = folder.Id != id && folder.OrderAnchorTabId is { } anchor && movedIds.Contains(anchor) ? anchor : null
        })];
        BrowserTab[] members = [.. tabs.Where(tab => movedIds.Contains(tab.Id))];
        var remaining = tree.PreserveOrder(movedIds, tabs, moving);
        remaining.RemoveAll(folder => moving.Contains(folder.Id));
        var splits = members.Select(tab => tab.SplitGroupId).OfType<Guid>().ToHashSet();
        var taken = destination.tabs.Select(tab => tab.SplitGroupId).OfType<Guid>()
            .Concat(destination.splitGroups.Select(group => group.Id)).ToHashSet();
        var renamed = splits.Where(taken.Contains).ToDictionary(group => group, _ => ids.Next());
        HandSplitMetadataTo(destination, splits, renamed);
        tabs.RemoveAll(tab => movedIds.Contains(tab.Id));
        folders.Clear(); folders.AddRange(remaining);
        foreach (var tab in members) {
            tab.Place(placement, copies[tab.FolderId!.Value], now, preservesSplit: true);
            if (tab.SplitGroupId is { } group && renamed.TryGetValue(group, out var fresh)) tab.SetSplit(fresh);
        }
        destination.tabs.InsertRange(NextSection(destination.tabs, placement), members);
        destination.folders.AddRange(made);
        RepairSplitMembership();
        destination.RepairSplitMembership();
        return (shown is { } active && movedIds.Contains(active)
            ? fallback is { } next && tabs.Any(tab => tab.Id == next) ? next : null
            : shown, moved);
    }

    #endregion
}
