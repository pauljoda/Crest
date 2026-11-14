using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Groups, and every folder of the open tabs, go with their last tab, and
/// their going syncs as a deletion so another device never brings them back.
public sealed partial class BrowserContractsTests {
    /// The sync record of the folder `folder` names, or null when the journal holds none.
    private static JsonNode? FolderRecord(NativeSyncAuthority sync, Guid folder) => FolderRecord(sync.Snapshot, folder);

    private static JsonNode? FolderRecord(NativeSyncJournal journal, Guid folder) =>
        JsonNode.Parse(journal.Read())!["records"]!.AsArray().SingleOrDefault(record =>
            record!["id"]!["kind"]!.GetValue<string>() == "folder" && Guid.Parse(record["id"]!["value"]!.GetValue<string>()) == folder);

    [Fact]
    public void AGroupThatLosesItsLastTabIsDeletedForEveryDevice() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var (core, sync) = (device.Authority, Syncing(device.Authority));
        var window = device.Open(f.Space, (f.Space, f.Open));
        device.Send(new SetFolderGroup(device.Workspace, f.Space, f.OpenFolder, IsGroup: true));
        sync.Flush();
        Assert.True(FolderRecord(sync, f.OpenFolder)!["payload"]!["value"]!["isGroup"]!.GetValue<bool>());

        // Closing its last tab stages with the other closed tabs, whose records
        // only go as superseded, yet the group goes as an explicit deletion.
        device.Send(new CloseTabs(device.Workspace, window, f.Space, Picking(f.Filed, f.Last)));

        Assert.DoesNotContain(core.Current.Spaces[0].Folders, folder => folder.Id == f.OpenFolder);
        Assert.Equal("explicitDelete", FolderRecord(sync, f.OpenFolder)!["tombstone"]!["reason"]!.GetValue<string>());
    }

    /// A folder of the open tabs goes with its last tab, taking the empty
    /// folders inside it, and its going syncs as a deletion; a saved folder
    /// stays when it empties.
    [Fact]
    public void AnOpenFolderGoesWhenItsLastTabMovesOutButASavedFolderStays() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var (core, sync) = (device.Authority, Syncing(device.Authority));
        var inner = Guid.NewGuid();
        device.Send(new CreateFolder(device.Workspace, f.Space, inner, TabPlacement.Current, f.OpenFolder, "Inner",
            FolderState.DefaultColor, "folder", [], LeavesSplits: false));
        sync.Flush();

        // A single move stages once edits pause, not with its save.
        device.Send(new MoveTab(device.Workspace, f.Space, f.Filed, TabPlacement.Pinned, null, null, LeavesSplit: false));
        device.Send(new MoveTab(device.Workspace, f.Space, f.Saved, TabPlacement.Current, null, null, LeavesSplit: false));
        sync.Flush();

        var folders = core.Current.Spaces[0].Folders;
        Assert.DoesNotContain(folders, held => held.Id == f.OpenFolder || held.Id == inner);
        Assert.Contains(folders, held => held.Id == f.SavedFolder);
        Assert.Equal("explicitDelete", FolderRecord(sync, f.OpenFolder)!["tombstone"]!["reason"]!.GetValue<string>());
        Assert.NotNull(FolderRecord(sync, f.SavedFolder)!["payload"]);
    }

    /// A new tab the person opens from a tab in a folder joins that folder at
    /// its end: a Start Page reuses the one the folder holds, a copy stays
    /// beside its source, and a link, a typed address or a Start Page from a
    /// saved folder's tab is saved there and belongs to the first page it
    /// shows. A tab opened for
    /// anyone else, and the Start Page a window shows on launch, stay outside.
    [Fact]
    public void ANewTabFromATabInAFolderJoinsThatFolderAtItsEnd() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        TabState Held(Guid tab) => core.Current.Spaces[0].Tabs.Single(held => held.Id == tab);
        Guid[] Inside(Guid folder) => [.. core.Current.Spaces[0].Tabs.Where(tab => tab.FolderId == folder).Select(tab => tab.Id)];
        var open = device.Open(f.Space, (f.Space, f.Filed));

        var page = Guid.NewGuid();
        device.Send(new ShowStartPage(device.Workspace, open, f.Space, page, OutsideSplits: false, JoinsFolder: true));
        device.Send(new ShowStartPage(device.Workspace, open, f.Space, Guid.NewGuid(), OutsideSplits: false, JoinsFolder: true));
        var before = core.Current.Spaces[0].Tabs.Select(tab => tab.Id).ToHashSet();
        device.Send(new DuplicateTab(device.Workspace, open, f.Space, f.Filed, Placement: null, Shows: false));
        var copy = core.Current.Spaces[0].Tabs.Single(tab => !before.Contains(tab.Id)).Id;
        Assert.Equal([f.Filed, page, copy], Inside(f.OpenFolder));
        Assert.Equal(TabPlacement.Current, Held(page).Placement);

        var saved = device.Open(f.Space, (f.Space, f.Saved));
        var (link, other, savedPage) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        device.Send(new OpenTab(device.Workspace, saved, f.Space, link, new TabContent("https://example.com/link", View: null, Title: null),
            TabPlacement.Current, AfterTabId: f.Saved, Shows: false, JoinsFolder: true));
        device.Send(new OpenTab(device.Workspace, saved, f.Space, other, new TabContent("https://example.com/other", View: null, Title: null),
            TabPlacement.Current, AfterTabId: f.Saved, Shows: false));
        device.Send(new ShowStartPage(device.Workspace, saved, f.Space, savedPage, OutsideSplits: false, JoinsFolder: true));
        device.Send(new NavigateTab(device.Workspace, f.Space, savedPage, "https://example.org/"));
        Assert.Equal([f.Saved, link, savedPage], Inside(f.SavedFolder));
        Assert.Equal((TabPlacement.Saved, "https://example.com/link"), (Held(link).Placement, Held(link).SavedUrl));
        Assert.Equal((TabPlacement.Saved, "https://example.org/"), (Held(savedPage).Placement, Held(savedPage).SavedUrl));
        Assert.Equal((TabPlacement.Current, (Guid?)null), (Held(other).Placement, Held(other).FolderId));
        var typed = Guid.NewGuid();
        device.Send(new OpenAddress(device.Workspace, saved, f.Space, typed, "https://example.com/typed", JoinsFolder: true));
        Assert.Equal([f.Saved, link, savedPage, typed], Inside(f.SavedFolder));

        var launched = Guid.NewGuid();
        device.Send(new ShowStartPage(device.Workspace, saved, f.Space, launched, OutsideSplits: false));
        Assert.Equal((TabPlacement.Current, (Guid?)null), (Held(launched).Placement, Held(launched).FolderId));
    }

    /// A Group another device emptied stays here while only its tabs' moves
    /// have arrived, since records come over several batches and the tab that
    /// keeps it may still be on its way; it goes with the deletion the device
    /// that emptied it stages.
    [Fact]
    public void AGroupAnotherDeviceEmptiedGoesOnlyWithThatDevicesDeletion() {
        const double now = 811679532;
        var f = new BatchSpace();
        var grouped = NativeSessionMaintenance.Repair(f.Session.DeepClone().AsObject(), now)["session"]!;
        grouped["spaces"]![0]!["folders"]!.AsArray().Single(folder => JsonNode.DeepEquals(folder!["id"], SwiftId(f.OpenFolder)))!
            ["isGroup"] = true;
        var emptied = grouped.DeepClone();
        var moved = emptied["spaces"]![0]!["tabs"]!.AsArray().Single(tab => JsonNode.DeepEquals(tab!["folderID"], SwiftId(f.OpenFolder)))!;
        moved["folderID"] = null;
        moved["positionModifiedAt"] = now;
        var deleted = emptied.DeepClone();
        deleted["spaces"]![0]!["folders"]!.AsArray().Remove(deleted["spaces"]![0]!["folders"]!.AsArray()
            .Single(folder => JsonNode.DeepEquals(folder!["id"], SwiftId(f.OpenFolder))));
        NativeSyncJournal Staged(NativeSyncJournal journal, JsonNode session, SyncDeletionReason reason) =>
            journal.Stage(session.DeepClone().AsObject(), reason, now);
        JsonNode Records(NativeSyncJournal journal) => JsonNode.Parse(journal.Read())!["records"]!;
        var sender = Staged(NativeSyncJournal.Fresh(Guid.NewGuid()), grouped, SyncDeletionReason.Superseded);
        var tabMoved = Staged(sender, emptied, SyncDeletionReason.Superseded);
        var groupDeleted = Staged(tabMoved, deleted, SyncDeletionReason.ExplicitDelete);
        NativeSyncSessionTransition Received(NativeSyncSessionTransition seen, NativeSyncJournal from) =>
            NativeSyncSessionTransition.Prepare(seen.Journal, seen.Session, Records(from).AsArray(), replacing: false,
                StoredSessionCodec.Date(now), emptySpace: null, access: null, new TestIds());

        var seen = Transition(NativeSyncJournal.Fresh(Guid.NewGuid()), grouped, Records(sender), replacing: true, now);
        var afterMove = Received(seen, tabMoved);
        Assert.Contains(afterMove.Session.Spaces[0].Folders, folder => folder.Id == f.OpenFolder && folder.IsGroup);
        Assert.NotNull(FolderRecord(afterMove.Journal, f.OpenFolder)!["payload"]);

        var afterDeletion = Received(afterMove, groupDeleted);
        Assert.DoesNotContain(afterDeletion.Session.Spaces[0].Folders, folder => folder.Id == f.OpenFolder);
        Assert.Equal("explicitDelete", FolderRecord(afterDeletion.Journal, f.OpenFolder)!["tombstone"]!["reason"]!.GetValue<string>());
    }
}
