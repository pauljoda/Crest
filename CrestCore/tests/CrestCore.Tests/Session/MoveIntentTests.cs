using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Moving one tab to another Space, and to another window: which workspace
/// holds it afterwards, what each window shows, what is on disk when the
/// intent returns, and the boundaries a tab never crosses.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void AMoveToAnotherWorkspacesWindowIsOnDiskWithItsJournalBeforeItReturnsOrNeitherWorkspaceChanges() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        document.Remove("disposableSeedMarker");
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var answered = app.Send(Adoption(document));
        var (workspace, opened) = TestWorkspaces.OpenStored(app);
        var owner = app.Workspace(workspace);
        var sync = app.StoredSync!;
        sync.Flush();
        _ = DrainLaunch(app, [.. answered, .. opened]);
        var borrowing = TestWorkspaces.Borrow(app, workspace, document["spaces"]![0]!);
        var borrowed = app.Workspace(borrowing);
        var windows = new Dictionary<Guid, WindowState>();
        void Record(IReadOnlyList<Change> changes) {
            foreach (var change in changes.OfType<WindowChanged>()) windows[change.Window.Id] = change.Window;
        }
        Guid window = Guid.NewGuid(), elsewhere = Guid.NewGuid();
        Record(app.Send(new OpenWindow(window, workspace, Saved: false, CopyingWindowId: null, fixture.Space,
            [new ShownTab(fixture.Space, fixture.Tab)], RestoresTabs: true)));
        Record(app.Send(new OpenWindow(elsewhere, borrowing, Saved: false, CopyingWindowId: null, fixture.Space, [], RestoresTabs: true)));
        var leaving = new MoveTabToWindow(workspace, window, fixture.Space, fixture.Tab, elsewhere);
        var (stored, staged, kept, lent) = (StoredParts(directory.File), sync.Snapshot, owner.Current, borrowed.Current);

        // The owner's save fails, so neither workspace changes.
        RefuseWrites(directory.File, "core");
        Assert.IsType<SaveFailed>(Assert.Throws<Rejected>(() => app.Send(leaving)).Rejection);
        Assert.Same(kept, owner.Current);
        Assert.Same(lent, borrowed.Current);
        Assert.Same(staged, sync.Snapshot);
        AssertSameParts(stored, StoredParts(directory.File));

        AcceptWrites(directory.File);
        Record(app.Send(leaving));
        var parts = StoredParts(directory.File);
        Assert.True(parts["core"].AsSpan().SequenceEqual(owner.Checkpoint().Read("core")));
        Assert.True(parts["journal"].AsSpan().SequenceEqual(sync.Snapshot.Read()));
        Assert.DoesNotContain(owner.Current.Spaces[0].Tabs, tab => tab.Id == fixture.Tab);
        Assert.Empty(owner.Current.Spaces[0].ArchivedTabs);
        var moved = Assert.Single(borrowed.Current.Spaces[0].Tabs);
        Assert.Equal((fixture.Tab, TabPlacement.Current, (Guid?)null, (string?)null), (moved.Id, moved.Placement, moved.FolderId, moved.SavedUrl));
        // The window the tab left shows none there; the other shows it.
        Assert.Null(windows[window].ShownTabs.Single(tab => tab.SpaceId == fixture.Space).TabId);
        Assert.Equal((fixture.Space, (Guid?)fixture.Tab),
            (windows[elsewhere].ShownSpaceId, windows[elsewhere].ShownTabs.Single(tab => tab.SpaceId == fixture.Space).TabId));

        // Back to the owner, saved again before the intent returns.
        Record(app.Send(new MoveTabToWindow(borrowing, elsewhere, fixture.Space, fixture.Tab, window)));
        Assert.Empty(borrowed.Current.Spaces[0].Tabs);
        Assert.Contains(owner.Current.Spaces[0].Tabs, tab => tab.Id == fixture.Tab);
        Assert.True(StoredParts(directory.File)["core"].AsSpan().SequenceEqual(owner.Checkpoint().Read("core")));
        Assert.Equal(fixture.Tab, windows[window].ShownTabs.Single(tab => tab.SpaceId == fixture.Space).TabId);
    }

    [Fact]
    public void ATabNeverMovesBetweenPrivateAndOtherBrowsingOrBetweenWorkspacesThatShareNoSpace() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        using var device = new TestDevice(session);
        var owner = device.Authority;
        var window = device.Showing(session);
        var space = session["spaces"]![0]!;
        var privateOwner = device.Attach(session.DeepClone(), WorkspaceKind.Private);
        var privateWindow = device.OpenIn(device.Borrow(space, privateOwner), fixture.Space);
        var unrelatedOwner = device.Attach(session.DeepClone());
        var unrelatedWindow = device.OpenIn(device.Borrow(space, unrelatedOwner), fixture.Space);
        MoveTabToWindow Moving(Guid destination) => new(device.Workspace, window, fixture.Space, fixture.Tab, destination);
        var before = owner.Current;

        Assert.IsType<PrivateWorkspaceBoundary>(Assert.Throws<Rejected>(() => device.Send(Moving(privateWindow))).Rejection);
        Assert.IsType<UnrelatedWorkspaces>(device.Query(new CanSend(Moving(unrelatedWindow))).Refusal);
        var gone = Guid.NewGuid();
        Assert.Equal(gone, Assert.IsType<WindowNotOpen>(Assert.Throws<Rejected>(() => device.Send(Moving(gone))).Rejection).WindowId);
        Assert.Same(before, owner.Current);

        // A window over the same workspace shows the tab, which stays where it is.
        var other = device.Open(fixture.Space);
        device.Send(Moving(other));
        Assert.Equal(fixture.Tab, device.Tab(other, fixture.Space));
        Assert.Equal(fixture.Tab, device.Tab(window, fixture.Space));
        Assert.Contains(owner.Current.Spaces[0].Tabs, tab => tab.Id == fixture.Tab);
    }

    [Fact]
    public void AMoveToAnotherSpaceTakesASplitMemberOutOfItsSplitAndFollowsAsTheLinkPreferencesSay() {
        var f = new BatchSpace();
        var other = f.Session["spaces"]![1]!["tabs"]!.AsArray();
        for (var index = 0; index < TabPlacement.PinnedCapacity; index++)
            other.Add(new JsonObject {
                ["id"] = SwiftId(Guid.NewGuid()),
                ["title"] = "Pinned",
                ["url"] = $"https://pinned{index}.example/",
                ["savedURL"] = $"https://pinned{index}.example/",
                ["placement"] = "pinned",
                ["symbol"] = "globe",
                ["lastActivatedAt"] = 800000000.0
            });
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        device.Send(new ShowTab(window, f.Space, f.Left));
        MoveTabToSpace Moving(Guid tab, Guid destination, TabPlacement? placement = null) =>
            new(device.Workspace, window, f.Space, tab, destination, placement, null, null);
        var before = core.Current;

        Assert.Equal(f.Space, Assert.IsType<AlreadyInSpace>(Assert.Throws<Rejected>(() =>
            device.Send(Moving(f.Left, f.Space))).Rejection).SpaceId);
        Assert.Equal(TabPlacement.PinnedCapacity, Assert.IsType<PinnedTabsFull>(device.Query(new CanSend(
            Moving(f.Left, f.Other, TabPlacement.Pinned))).Refusal).Capacity);
        Assert.Same(before, core.Current);

        // The window gives up the tab it showed for the one it showed before.
        device.Send(new SetLinkBehavior(LinkBehavior.FollowsMovedTabs, IsOn: false));
        device.Send(Moving(f.Left, f.Other));
        var moved = core.Current.Spaces[1].Tabs.Single(tab => tab.Id == f.Left);
        Assert.Equal((TabPlacement.Current, (Guid?)null), (moved.Placement, moved.SplitGroupId));
        Assert.Equal((f.Space, (Guid?)f.Open), (device.Space(window), device.Tab(window, f.Space)));

        // The window follows a moved tab when the device's link preferences say so.
        device.Send(new SetLinkBehavior(LinkBehavior.FollowsMovedTabs, IsOn: true));
        device.Send(Moving(f.Last, f.Other));
        Assert.Equal((f.Other, (Guid?)f.Last), (device.Space(window), device.Tab(window, f.Other)));
        Assert.Equal([f.Resident, f.Left, f.Last], core.Current.Spaces[1].Tabs.Where(tab => tab.Placement == TabPlacement.Current)
            .Select(tab => tab.Id));
    }

    [Fact]
    public void AFolderMovesToAnotherSpaceWholeWithItsSplitsUnderNewFolderIdentities() {
        var f = new BatchSpace();
        var inner = f.Nest();
        using var device = new TestDevice(f.Session);
        var (core, sync) = (device.Authority, Syncing(device.Authority));
        var window = device.Open(f.Space, (f.Space, f.Open));
        device.Send(new ShowTab(window, f.Space, inner.Right));
        device.Send(new SetLinkBehavior(LinkBehavior.FollowsMovedTabs, IsOn: true));
        MoveFolderToSpace Moving(Guid folder, Guid destination) => new(device.Workspace, window, f.Space, folder, destination);
        var unknown = Guid.NewGuid();
        var before = core.Current;

        Assert.Equal(f.Space, Assert.IsType<AlreadyInSpace>(Assert.Throws<Rejected>(() =>
            device.Send(Moving(f.OpenFolder, f.Space))).Rejection).SpaceId);
        Assert.Equal(unknown, Assert.IsType<UnknownFolder>(device.Query(new CanSend(Moving(unknown, f.Other))).Refusal).FolderId);
        Assert.Same(before, core.Current);

        device.Send(Moving(f.OpenFolder, f.Other));
        var (source, destination) = (core.Current.Spaces[0], core.Current.Spaces[1]);
        // Nothing of the folder is left behind, its split's metadata included.
        Assert.Equal([f.SavedFolder], source.Folders.Select(folder => folder.Id));
        Assert.Equal([f.Pinned, f.Saved, f.Open, f.Left, f.Right, f.Last], Tabs(core));
        Assert.Equal([f.Split], source.SplitGroups.Select(group => group.Id));
        // The folders keep their tree, titles and disclosure under new
        // identities, after what the open tabs held there.
        var (outer, nested) = (destination.Folders[0], destination.Folders[1]);
        Assert.DoesNotContain(outer.Id, new[] { f.OpenFolder, inner.Folder });
        Assert.DoesNotContain(nested.Id, new[] { f.OpenFolder, inner.Folder });
        Assert.Equal((TabPlacement.Current, (Guid?)null, false), (outer.Location, outer.ParentId, outer.IsCollapsed));
        Assert.Equal((TabPlacement.Current, (Guid?)outer.Id, "Inner", true), (nested.Location, nested.ParentId, nested.Title, nested.IsCollapsed));
        Assert.Equal([f.Resident, f.Filed, inner.Left, inner.Right], Tabs(core, 1));
        Assert.Equal(new Guid?[] { null, outer.Id, nested.Id, nested.Id }, destination.Tabs.Select(tab => tab.FolderId));
        // The split moves whole with what was chosen for it, and its tabs keep
        // their state.
        Assert.Equal(new Guid?[] { inner.Split, inner.Split }, destination.Tabs.Skip(2).Select(tab => tab.SplitGroupId));
        var split = Assert.Single(destination.SplitGroups);
        Assert.Equal((inner.Split, "Reading", true), (split.Id, split.CustomTitle, split.IsCollapsed));
        Assert.All(destination.Tabs.Skip(1), tab => Assert.Equal(before.Spaces[0].Tabs.Single(old => old.Id == tab.Id).Url, tab.Url));
        // The window follows the tab it showed, and shows the one it showed
        // before in the Space the folder left.
        Assert.Equal((f.Other, (Guid?)inner.Right), (device.Space(window), device.Tab(window, f.Other)));
        Assert.Equal(f.Open, device.Tab(window, f.Space));
        // Other devices delete the folders it left and receive the tabs in
        // their new Space.
        foreach (var folder in new[] { f.OpenFolder, inner.Folder })
            Assert.Equal("explicitDelete", Journaled(sync, "folder", folder)["tombstone"]!["reason"]!.GetValue<string>());
        foreach (var folder in new[] { outer.Id, nested.Id }) Assert.NotNull(Journaled(sync, "folder", folder)["payload"]);
        foreach (var tab in new[] { f.Filed, inner.Left, inner.Right })
            Assert.Equal(f.Other, Guid.Parse(Journaled(sync, "tab", tab)["spaceID"]!["rawValue"]!.GetValue<string>()));
    }
}
