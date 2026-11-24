using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using CrestCore.Tests.Session;

using Xunit;

namespace CrestCore.Tests;

/// Groups, and every folder of the open tabs, go with their last tab. Their
/// records stay, marked emptied, so a device that still holds a tab in one
/// keeps it, and every other device leaves it out while it holds nothing.
public sealed partial class BrowserContractsTests {
    /// The sync record of the folder `folder` names, or null when the journal holds none.
    private static JsonNode? FolderRecord(NativeSyncAuthority sync, Guid folder) => FolderRecord(sync.Snapshot, folder);

    /// The value of the live record of the folder `folder` names, which must
    /// be live.
    private static JsonNode FolderValue(NativeSyncAuthority sync, Guid folder) {
        var record = FolderRecord(sync, folder)!;
        Assert.Null(record["tombstone"]);
        return record["payload"]!["value"]!;
    }

    private static JsonNode? FolderRecord(NativeSyncJournal journal, Guid folder) =>
        JsonNode.Parse(journal.Read())!["records"]!.AsArray().SingleOrDefault(record =>
            record!["id"]!["kind"]!.GetValue<string>() == "folder" && Guid.Parse(record["id"]!["value"]!.GetValue<string>()) == folder);

    /// Closing a Group's last tab takes the Group off this device and keeps
    /// its record, marked emptied, though the close stages as a deletion. A
    /// later deletion the person makes elsewhere in the Space leaves that
    /// record as it is, since a session lacking it is no evidence it went.
    [Fact]
    public void AGroupThatLosesItsLastTabGoesButKeepsItsRecordMarkedEmptied() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var (core, sync) = (device.Authority, Syncing(device.Authority));
        var window = device.Open(f.Space, (f.Space, f.Open));
        device.Send(new SetFolderGroup(device.Workspace, f.Space, f.OpenFolder, IsGroup: true));
        sync.Flush();
        Assert.True(FolderValue(sync, f.OpenFolder)["isGroup"]!.GetValue<bool>());
        Assert.Null(FolderValue(sync, f.OpenFolder)["emptiedAt"]);

        device.Send(new CloseTabs(device.Workspace, window, f.Space, Picking(f.Filed, f.Last)));

        Assert.DoesNotContain(core.Current.Spaces[0].Folders, folder => folder.Id == f.OpenFolder);
        var marked = FolderValue(sync, f.OpenFolder);
        Assert.True(marked["isGroup"]!.GetValue<bool>());
        Assert.NotNull(marked["emptiedAt"]);

        device.Send(new CloseTabs(device.Workspace, window, f.Space, Picking(f.Left, f.Right)));
        sync.Flush();
        Assert.True(JsonNode.DeepEquals(marked, FolderValue(sync, f.OpenFolder)));
    }

    /// A folder of the open tabs goes once nothing is left in it and keeps its
    /// record, marked emptied; a saved folder stays when it empties. A folder
    /// that still holds a folder stays, and so does that folder, even empty.
    [Fact]
    public void AnOpenFolderGoesOnceNothingIsLeftInItButASavedFolderStays() {
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
        Assert.Contains(folders, held => held.Id == f.OpenFolder);
        Assert.Contains(folders, held => held.Id == inner && held.ParentId == f.OpenFolder);
        Assert.Contains(folders, held => held.Id == f.SavedFolder);

        device.Send(new DeleteFolder(device.Workspace, f.Space, inner));
        sync.Flush();
        Assert.DoesNotContain(core.Current.Spaces[0].Folders, held => held.Id == f.OpenFolder || held.Id == inner);
        Assert.NotNull(FolderValue(sync, f.OpenFolder)["emptiedAt"]);
        Assert.Equal("explicitDelete", FolderRecord(sync, inner)!["tombstone"]!["reason"]!.GetValue<string>());
        Assert.Null(FolderValue(sync, f.SavedFolder)["emptiedAt"]);
    }

    /// A folder whose tabs all sit in a folder inside it stays while that
    /// folder does, and goes once that folder moves out.
    [Fact]
    public void AFolderGoesOnceItsLastFolderMovesOut() {
        var f = new BatchSpace();
        var (nested, _, _, _) = f.Nest();
        using var device = new TestDevice(f.Session);
        var (core, sync) = (device.Authority, Syncing(device.Authority));

        device.Send(new MoveTab(device.Workspace, f.Space, f.Filed, TabPlacement.Pinned, null, null, LeavesSplit: false));
        sync.Flush();
        Assert.Contains(core.Current.Spaces[0].Folders, held => held.Id == f.OpenFolder);

        device.Send(new MoveFolder(device.Workspace, f.Space, nested, TabPlacement.Current, null, null, null));
        sync.Flush();
        var folders = core.Current.Spaces[0].Folders;
        Assert.DoesNotContain(folders, held => held.Id == f.OpenFolder);
        Assert.Contains(folders, held => held.Id == nested && held.ParentId is null);
        Assert.NotNull(FolderValue(sync, f.OpenFolder)["emptiedAt"]);
    }

    /// A new tab the person opens from a tab in a folder opens at the top of the
    /// open tabs, or at the bottom when they chose so, unless they chose to open
    /// new tabs in the current folder. Then one
    /// from a tab in a folder of the open tabs joins that folder at its end: a
    /// Start Page reuses the one the folder holds, and a copy stays beside its
    /// source. From a saved folder's tab, a Start Page or a typed address,
    /// shown or opened behind, is saved there and belongs to the first page it
    /// shows, while a link and a copy open among the open tabs. A tab opened
    /// for anyone else stays outside, and the Start Page a window shows on
    /// launch is the Space's open one, wherever it sits.
    [Fact]
    public void ANewTabFromATabInAFolderJoinsThatFolderAtItsEndOnlyWhenChosen() {
        var f = new BatchSpace();
        using (var plain = new TestDevice(f.Session)) {
            var tabs = plain.Authority.Current.Spaces[0].Tabs.Select(tab => tab.Id).ToHashSet();
            var (fromFiled, fromSaved) = (plain.Open(f.Space, (f.Space, f.Filed)), plain.Open(f.Space, (f.Space, f.Saved)));
            plain.Send(new ShowStartPage(plain.Workspace, fromFiled, f.Space, Guid.NewGuid(), OutsideSplits: false, PlacesAsNewTab: true));
            plain.Send(new OpenTab(plain.Workspace, fromFiled, f.Space, Guid.NewGuid(),
                new TabContent("https://example.com/link", View: null, Title: null), TabPlacement.Current, AfterTabId: f.Filed,
                Shows: false, PlacesAsNewTab: true, SavesInSavedFolder: true));
            plain.Send(new DuplicateTab(plain.Workspace, fromFiled, f.Space, f.Filed, Placement: null, Shows: false));
            plain.Send(new OpenAddress(plain.Workspace, fromSaved, f.Space, Guid.NewGuid(), "https://example.com/typed", PlacesAsNewTab: true));
            var opened = plain.Authority.Current.Spaces[0].Tabs.Where(tab => !tabs.Contains(tab.Id)).ToArray();
            Assert.Equal(4, opened.Length);
            Assert.All(opened, tab => Assert.Equal((TabPlacement.Current, (Guid?)null), (tab.Placement, tab.FolderId)));
            Guid[] OpenTabs() => [.. plain.Authority.Current.Spaces[0].Tabs.Where(tab => tab.Placement == TabPlacement.Current)
                .Select(tab => tab.Id)];
            Assert.Equal(opened.Select(tab => tab.Id).ToHashSet(), OpenTabs().Take(4).ToHashSet());

            plain.Send(new SetAppPreferences(plain.Workspace, AppPreferences.Default with { NewTabPosition = NewTabPosition.Bottom }));
            var last = Guid.NewGuid();
            plain.Send(new OpenTab(plain.Workspace, fromFiled, f.Space, last,
                new TabContent("https://example.com/last", View: null, Title: null), TabPlacement.Current, AfterTabId: f.Filed,
                Shows: false, PlacesAsNewTab: true));
            Assert.Equal(last, OpenTabs()[^1]);
        }

        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { NewTabsJoinFolder = true }));
        TabState Held(Guid tab) => core.Current.Spaces[0].Tabs.Single(held => held.Id == tab);
        Guid[] Inside(Guid folder) => [.. core.Current.Spaces[0].Tabs.Where(tab => tab.FolderId == folder).Select(tab => tab.Id)];
        var open = device.Open(f.Space, (f.Space, f.Filed));

        var page = Guid.NewGuid();
        device.Send(new ShowStartPage(device.Workspace, open, f.Space, page, OutsideSplits: false, PlacesAsNewTab: true));
        device.Send(new ShowStartPage(device.Workspace, open, f.Space, Guid.NewGuid(), OutsideSplits: false, PlacesAsNewTab: true));
        var before = core.Current.Spaces[0].Tabs.Select(tab => tab.Id).ToHashSet();
        device.Send(new DuplicateTab(device.Workspace, open, f.Space, f.Filed, Placement: null, Shows: false));
        var copy = core.Current.Spaces[0].Tabs.Single(tab => !before.Contains(tab.Id)).Id;
        Assert.Equal([f.Filed, page, copy], Inside(f.OpenFolder));
        Assert.Equal(TabPlacement.Current, Held(page).Placement);

        var saved = device.Open(f.Space, (f.Space, f.Saved));
        var (link, savedPage) = (Guid.NewGuid(), Guid.NewGuid());
        device.Send(new OpenTab(device.Workspace, saved, f.Space, link, new TabContent("https://example.com/link", View: null, Title: null),
            TabPlacement.Current, AfterTabId: f.Saved, Shows: false, PlacesAsNewTab: true));
        before = core.Current.Spaces[0].Tabs.Select(tab => tab.Id).ToHashSet();
        device.Send(new DuplicateTab(device.Workspace, saved, f.Space, f.Saved, Placement: null, Shows: false));
        var savedCopy = core.Current.Spaces[0].Tabs.Single(tab => !before.Contains(tab.Id)).Id;
        device.Send(new ShowStartPage(device.Workspace, saved, f.Space, savedPage, OutsideSplits: false, PlacesAsNewTab: true));
        device.Send(new NavigateTab(device.Workspace, f.Space, savedPage, "https://example.org/"));
        Assert.Equal([f.Saved, savedPage], Inside(f.SavedFolder));
        Assert.Equal((TabPlacement.Saved, "https://example.org/"), (Held(savedPage).Placement, Held(savedPage).SavedUrl));
        Assert.Equal((TabPlacement.Current, (Guid?)null), (Held(link).Placement, Held(link).FolderId));
        Assert.Equal((TabPlacement.Current, (Guid?)null), (Held(savedCopy).Placement, Held(savedCopy).FolderId));
        var (typed, behind) = (Guid.NewGuid(), Guid.NewGuid());
        device.Send(new OpenAddress(device.Workspace, saved, f.Space, typed, "https://example.com/typed", PlacesAsNewTab: true));
        device.Send(new OpenTab(device.Workspace, saved, f.Space, behind, new TabContent("https://example.com/behind", View: null, Title: null),
            TabPlacement.Current, AfterTabId: f.Saved, Shows: false, PlacesAsNewTab: true, SavesInSavedFolder: true));
        Assert.Equal([f.Saved, savedPage, typed, behind], Inside(f.SavedFolder));
        Assert.Equal((TabPlacement.Saved, "https://example.com/behind"), (Held(behind).Placement, Held(behind).SavedUrl));

        var launched = device.Open(f.Space, (f.Space, f.Last));
        device.Send(new ShowStartPage(device.Workspace, launched, f.Space, Guid.NewGuid(), OutsideSplits: false));
        Assert.Equal(page, device.Tab(launched, f.Space));
    }

    /// A Group another device emptied waits out of sight here once its tabs'
    /// moves arrive, and stays out of sight once that device's mark arrives,
    /// with its record kept throughout, since records come over several
    /// batches and the tab that keeps it may still be on its way.
    [Fact]
    public void AGroupAnotherDeviceEmptiedWaitsOutOfSightWithItsRecordKept() {
        const double now = 811679532;
        var f = new BatchSpace();
        var grouped = StoredSessionMaintenance.Repair(f.Session.DeepClone().AsObject(), now)["session"]!;
        grouped["spaces"]![0]!["folders"]!.AsArray().Single(folder => JsonNode.DeepEquals(folder!["id"], SwiftId(f.OpenFolder)))!
            ["isGroup"] = true;
        var emptied = grouped.DeepClone();
        var moved = emptied["spaces"]![0]!["tabs"]!.AsArray().Single(tab => JsonNode.DeepEquals(tab!["folderID"], SwiftId(f.OpenFolder)))!;
        moved["folderID"] = null;
        moved["positionModifiedAt"] = now;
        var gone = emptied.DeepClone();
        gone["spaces"]![0]!["folders"]!.AsArray().Remove(gone["spaces"]![0]!["folders"]!.AsArray()
            .Single(folder => JsonNode.DeepEquals(folder!["id"], SwiftId(f.OpenFolder))));
        NativeSyncJournal Staged(NativeSyncJournal journal, JsonNode session, SyncDeletionReason reason, params Guid[] emptying) =>
            journal.Stage(session.DeepClone().AsObject(), reason, now,
                emptied: emptying.Select(SyncRecordKind.Folder.RecordName).ToHashSet(StringComparer.Ordinal));
        JsonNode Records(NativeSyncJournal journal) => JsonNode.Parse(journal.Read())!["records"]!;
        var sender = Staged(NativeSyncJournal.Fresh(Guid.NewGuid()), grouped, SyncDeletionReason.Superseded);
        var tabMoved = Staged(sender, emptied, SyncDeletionReason.Superseded);
        var groupEmptied = Staged(tabMoved, gone, SyncDeletionReason.ExplicitDelete, f.OpenFolder);
        NativeSyncSessionTransition Received(NativeSyncSessionTransition seen, NativeSyncJournal from) =>
            NativeSyncSessionTransition.Prepare(seen.Journal, seen.Session, Records(from).AsArray(), replacing: false,
                StoredSessionCodec.Date(now), emptySpace: null, access: null, new TestIds());

        var seen = Transition(NativeSyncJournal.Fresh(Guid.NewGuid()), grouped, Records(sender), replacing: true, now);
        var afterMove = Received(seen, tabMoved);
        Assert.DoesNotContain(afterMove.Session.Spaces[0].Folders, folder => folder.Id == f.OpenFolder);
        Assert.Null(FolderRecord(afterMove.Journal, f.OpenFolder)!["payload"]!["value"]!["emptiedAt"]);

        var afterMark = Received(afterMove, groupEmptied);
        Assert.DoesNotContain(afterMark.Session.Spaces[0].Folders, folder => folder.Id == f.OpenFolder);
        var record = FolderRecord(afterMark.Journal, f.OpenFolder)!;
        Assert.Null(record["tombstone"]);
        Assert.NotNull(record["payload"]!["value"]!["emptiedAt"]);
    }
}
