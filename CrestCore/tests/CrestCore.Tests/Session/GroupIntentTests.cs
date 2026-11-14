using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Groups: folders of open tabs that go with their last tab, and whose going
/// syncs as a deletion so another device never brings them back.
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

    [Fact]
    public void AGroupGoesWhenItsLastTabMovesOutButAFolderStays() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var (core, sync) = (device.Authority, Syncing(device.Authority));
        var folder = Guid.NewGuid();
        device.Send(new CreateFolder(device.Workspace, f.Space, folder, TabPlacement.Current, null, "Plain",
            FolderState.DefaultColor, "folder", [f.Last], LeavesSplits: false));
        device.Send(new SetFolderGroup(device.Workspace, f.Space, f.OpenFolder, IsGroup: true));
        sync.Flush();

        // A single move stages once edits pause, not with its save.
        device.Send(new MoveTab(device.Workspace, f.Space, f.Filed, TabPlacement.Pinned, null, null, LeavesSplit: false));
        device.Send(new MoveTab(device.Workspace, f.Space, f.Last, TabPlacement.Current, null, null, LeavesSplit: false));
        sync.Flush();

        var folders = core.Current.Spaces[0].Folders;
        Assert.DoesNotContain(folders, held => held.Id == f.OpenFolder);
        Assert.Contains(folders, held => held.Id == folder);
        Assert.Equal("explicitDelete", FolderRecord(sync, f.OpenFolder)!["tombstone"]!["reason"]!.GetValue<string>());
        Assert.NotNull(FolderRecord(sync, folder)!["payload"]);
    }

    [Fact]
    public void AGroupAnotherDeviceEmptiedGoesOnceItsTabsArrive() {
        const double now = 811679532;
        var f = new BatchSpace();
        var grouped = NativeSessionMaintenance.Repair(f.Session.DeepClone().AsObject(), now)["session"]!;
        grouped["spaces"]![0]!["folders"]!.AsArray().Single(folder => JsonNode.DeepEquals(folder!["id"], SwiftId(f.OpenFolder)))!
            ["isGroup"] = true;
        // An older device files the group's last tab out and keeps the group.
        var emptied = grouped.DeepClone();
        var moved = emptied["spaces"]![0]!["tabs"]!.AsArray().Single(tab => JsonNode.DeepEquals(tab!["folderID"], SwiftId(f.OpenFolder)))!;
        moved["folderID"] = null;
        moved["positionModifiedAt"] = now;
        NativeSyncJournal Staged(NativeSyncJournal journal, JsonNode session) =>
            journal.Stage(session.DeepClone().AsObject(), SyncDeletionReason.Superseded, now);
        JsonNode Records(NativeSyncJournal journal) => JsonNode.Parse(journal.Read())!["records"]!;
        var sender = Staged(NativeSyncJournal.Fresh(Guid.NewGuid()), grouped);
        var later = Staged(sender, emptied);

        var seen = Transition(NativeSyncJournal.Fresh(Guid.NewGuid()), grouped, Records(sender), replacing: true, now);
        var received = NativeSyncSessionTransition.Prepare(seen.Journal, seen.Session, Records(later).AsArray(), replacing: false,
            StoredSessionCodec.Date(now), emptySpace: null, access: null, new TestIds());
        Assert.DoesNotContain(received.Session.Spaces[0].Folders, folder => folder.Id == f.OpenFolder);
        Assert.Equal("explicitDelete", FolderRecord(received.Journal, f.OpenFolder)!["tombstone"]!["reason"]!.GetValue<string>());
    }
}
