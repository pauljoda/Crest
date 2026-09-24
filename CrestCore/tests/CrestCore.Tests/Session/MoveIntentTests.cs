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
        using var app = new CrestApp(new AppConfiguration(directory.Path));
        var answered = app.Send(Adoption(document));
        var owner = app.Session!;
        var sync = app.SessionSync!;
        sync.Flush();
        _ = DrainUntil(app, changes => changes.OfType<SyncJournalChanged>().Any() && changes.OfType<Saved>().Any(), answered);
        var workspace = app.AttachWorkspace(owner);
        var profile = owner.Current.Spaces[0].ProfileId;
        var borrowed = owner.CreateBorrowed(fixture.Space, profile);
        var borrowing = app.AttachWorkspace(borrowed);
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
        var owner = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(owner);
        var window = device.Showing(session);
        var privateSession = session.DeepClone();
        privateSession["coreWorkspaceKind"] = "private";
        var privateOwner = new NativeSessionAuthority(Bytes(privateSession));
        device.Attach(privateOwner);
        var profile = owner.Current.Spaces[0].ProfileId;
        var privateWindow = device.OpenIn(device.Attach(privateOwner.CreateBorrowed(fixture.Space, profile)), fixture.Space);
        var unrelatedOwner = new NativeSessionAuthority(Bytes(session));
        device.Attach(unrelatedOwner);
        var unrelatedWindow = device.OpenIn(device.Attach(unrelatedOwner.CreateBorrowed(fixture.Space, profile)), fixture.Space);
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

        // A borrowing workspace that already holds the tab takes no second one.
        var lending = owner.CreateBorrowed(fixture.Space, profile);
        var lendingWindow = device.OpenIn(device.Attach(lending), fixture.Space);
        var space = session["spaces"]![0]!;
        lending.Commit(Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject {
                ["id"] = space["id"]!.DeepClone(),
                ["tabs"] = new JsonObject { ["replace"] = space["tabs"]!.DeepClone() }
            })
        }));
        Assert.Equal(fixture.Tab, Assert.IsType<TabAlreadyExists>(Assert.Throws<Rejected>(() =>
            device.Send(Moving(lendingWindow))).Rejection).TabId);
    }

    [Fact]
    public void AMoveToAnotherSpaceTakesASplitMemberOutOfItsSplitAndFollowsOnlyWhenAsked() {
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
        var core = new NativeSessionAuthority(Bytes(f.Session));
        using var device = new TestDevice(core);
        var window = device.Open(f.Space, (f.Space, f.Open));
        device.Send(new ShowTab(window, f.Space, f.Left));
        MoveTabToSpace Moving(Guid tab, Guid destination, bool follows, TabPlacement? placement = null) =>
            new(device.Workspace, window, f.Space, tab, destination, placement, null, null, follows);
        var before = core.Current;

        Assert.Equal(f.Space, Assert.IsType<AlreadyInSpace>(Assert.Throws<Rejected>(() =>
            device.Send(Moving(f.Left, f.Space, false))).Rejection).SpaceId);
        Assert.Equal(TabPlacement.PinnedCapacity, Assert.IsType<PinnedTabsFull>(device.Query(new CanSend(
            Moving(f.Left, f.Other, false, TabPlacement.Pinned))).Refusal).Capacity);
        Assert.Same(before, core.Current);

        // The window gives up the tab it showed for the one it showed before.
        device.Send(Moving(f.Left, f.Other, follows: false));
        var moved = core.Current.Spaces[1].Tabs.Single(tab => tab.Id == f.Left);
        Assert.Equal((TabPlacement.Current, (Guid?)null), (moved.Placement, moved.SplitGroupId));
        Assert.Equal((f.Space, (Guid?)f.Open), (device.Space(window), device.Tab(window, f.Space)));

        device.Send(Moving(f.Last, f.Other, follows: true));
        Assert.Equal((f.Other, (Guid?)f.Last), (device.Space(window), device.Tab(window, f.Other)));
        Assert.Equal([f.Resident, f.Left, f.Last], core.Current.Spaces[1].Tabs.Where(tab => tab.Placement == TabPlacement.Current)
            .Select(tab => tab.Id));
    }
}
