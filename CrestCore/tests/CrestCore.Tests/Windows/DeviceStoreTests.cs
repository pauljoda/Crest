using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The device store: what each window shows lives beside the session in its
/// file, never in the session, survives a relaunch, is repaired when the
/// session changes under it, and was carried once from the records an
/// installed release kept.
public sealed partial class BrowserContractsTests {
    /// An app over a new file holding the installed session, with its
    /// persistent workspace and the session's Spaces.
    private static (CrestApp App, Guid Workspace, JsonArray Spaces) DeviceApp(StorageDirectory directory, JsonObject? core = null) {
        var app = new CrestApp(new AppConfiguration(directory.Path));
        var (installedCore, installed, _) = InstalledDefaults();
        var session = core ?? installedCore;
        if (app.Session is null) app.Send(new AdoptLegacySession(installed with { Core = Bytes(session) }, SeedDocument()));
        var spaces = JsonNode.Parse(app.SessionProjection()!.Output)!["session"]!["spaces"]!.AsArray();
        return (app, app.AttachWorkspace(app.Session!), spaces);
    }

    private static Guid TabId(JsonNode space, int index) => SpaceId(space["tabs"]![index]!);

    private static WindowState Shown(IReadOnlyList<Change> changes) => Assert.IsType<WindowChanged>(changes[^1]).Window;

    private static Guid? ShownTab(WindowState window, Guid space) => window.ShownTabs.SingleOrDefault(tab => tab.SpaceId == space)?.TabId;

    [Fact]
    public void ASavedWindowReopensOnWhatItShowedAndTheSessionNeverHoldsIt() {
        using var directory = new StorageDirectory();
        var window = Guid.NewGuid();
        Guid second, tab, group;
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            second = SpaceId(spaces[1]!);
            tab = TabId(spaces[1]!, 3);
            group = Guid.Parse(spaces[0]!["splitGroups"]![0]!["id"]!["rawValue"]!.GetValue<string>());
            app.Send(new OpenWindow(window, workspace, Saved: true, CopyingWindowId: null, ShowingSpaceId: null, RestoresTabs: true));
            var touched = app.Send(new ShowTab(window, second, tab));
            Assert.Equal(tab, Assert.IsType<TabActivated>(touched[0]).TabId);
            Assert.Equal(second, Shown(touched).ShownSpaceId);
            var members = spaces[0]!["tabs"]!.AsArray().Count(item => item!["splitGroupID"]?["rawValue"]?.GetValue<string>() == group.ToString().ToUpperInvariant());
            var resized = Shown(app.Send(new ResizeSplitColumns(window, group, [.. Enumerable.Repeat(1.0, members)])));
            Assert.Equal(1.0 / members, resized.SplitColumnShares.Single().Shares[0], precision: 12);
            Assert.Equal([new WindowClosed(window)], app.Send(new CloseWindow(window)));
        }

        var parts = StoredParts(directory.File);
        Assert.DoesNotContain("selectedTabID", Encoding.UTF8.GetString(parts["core"]), StringComparison.Ordinal);
        using var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadOnly);
        Assert.Equal(1, connection.ReadUserVersion());

        var (relaunched, persistent, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        var restored = Shown(relaunched.Send(new OpenWindow(window, persistent, Saved: true, null, null, RestoresTabs: true)));
        Assert.Equal(second, restored.ShownSpaceId);
        Assert.Equal(tab, ShownTab(restored, second));
        Assert.Single(restored.SplitColumnShares);
        // A scene that restores only its Space keeps the Space and chooses tabs afresh.
        relaunched.Send(new CloseWindow(window));
        var spaceOnly = Shown(relaunched.Send(new OpenWindow(window, persistent, Saved: true, null, null, RestoresTabs: false)));
        Assert.Equal(second, spaceOnly.ShownSpaceId);
        Assert.Null(ShownTab(spaceOnly, second));
    }

    [Fact]
    public void WindowsFollowTheSessionAndOnlyTheOnesThatChangePublish() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var (first, second) = (SpaceId(spaces[0]!), SpaceId(spaces[1]!));
        Guid showing = Guid.NewGuid(), elsewhere = Guid.NewGuid();
        app.Send(new OpenWindow(showing, workspace, Saved: true, null, null, true));
        app.Send(new OpenWindow(elsewhere, workspace, Saved: false, null, null, true));
        var shownTab = TabId(spaces[1]!, 2);
        app.Send(new ShowTab(showing, second, shownTab));
        app.Send(new ShowTab(elsewhere, second, TabId(spaces[1]!, 0)));
        app.Send(new ShowSpace(elsewhere, first));
        _ = app.Drain();

        // Another window closes the tab this one shows: it shows nothing in that
        // Space, and the window that shows another Space is left alone.
        var session = app.Session!;
        var space = session.Current.Spaces[1];
        session.Commit(session.Revision, Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject {
                ["id"] = SwiftId(second),
                ["tabs"] = new JsonObject {
                    ["remove"] = new JsonArray(shownTab.ToString("D")),
                    ["upsert"] = new JsonArray(),
                    ["order"] = new JsonArray([.. space.Tabs.Where(tab => tab.Id != shownTab).Select(tab => (JsonNode)tab.Id.ToString("D"))])
                }
            })
        }));
        var repaired = Assert.Single(app.Drain().OfType<WindowChanged>()).Window;
        Assert.Equal(showing, repaired.Id);
        Assert.Null(ShownTab(repaired, second));
        Assert.Equal(space.Tabs.Count - 1, session.Current.Spaces[1].Tabs.Count);

        // Showing the Space again shows its fallback tab.
        app.Send(new ShowSpace(showing, first));
        var back = Shown(app.Send(new ShowSpace(showing, second)));
        Assert.Equal(Window.FallbackTab(session.Current.Spaces[1]), ShownTab(back, second));
        // A tab that is gone publishes nothing, and a window that is not open is refused.
        Assert.Empty(app.Send(new ShowTab(showing, second, shownTab)));
        Assert.Equal(new WindowNotOpen(Guid.Empty), Assert.Throws<Rejected>(() => app.Send(new ShowSpace(Guid.Empty, first))).Rejection);
    }

    [Fact]
    public void OnlyWindowsOverThePersistentSessionAreSavedAndTheStoreKeepsTheSixteenUsedLast() {
        using var directory = new StorageDirectory();
        var windows = Enumerable.Range(0, Device.MaximumSavedWindows + 1).Select(_ => Guid.NewGuid()).ToArray();
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            var memory = new NativeSessionAuthority(Bytes(SavedSession().Document["session"]!));
            var memoryWorkspace = app.AttachWorkspace(memory);
            Assert.Equal(memoryWorkspace, app.AttachWorkspace(memory));
            Assert.Equal(new UnsavedWorkspace(memoryWorkspace),
                Assert.Throws<Rejected>(() => app.Send(new OpenWindow(Guid.NewGuid(), memoryWorkspace, true, null, null, true))).Rejection);
            app.Send(new OpenWindow(Guid.NewGuid(), memoryWorkspace, Saved: false, null, null, true));
            foreach (var window in windows) app.Send(new OpenWindow(window, workspace, Saved: true, null, null, true));
            // Using the first window again keeps it; the second is now the oldest.
            app.Send(new ShowSpace(windows[0], SpaceId(spaces[1]!)));
            // A released session takes its windows with it.
            memory.Release();
        }
        using var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadOnly);
        var stored = connection.ReadDevice("window-records").Windows.Select(record => record.Id).ToHashSet();
        Assert.Equal(Device.MaximumSavedWindows, stored.Count);
        Assert.Contains(windows[0], stored);
        Assert.DoesNotContain(windows[1], stored);
    }

    [Fact]
    public void TheWindowRecordsAnInstalledReleaseKeptAreCarriedOnceWithTheirLayouts() {
        using var directory = new StorageDirectory();
        var (core, _, _) = InstalledDefaults();
        var spaces = core["spaces"]!.AsArray();
        var (first, second) = (SpaceId(spaces[0]!), SpaceId(spaces[1]!));
        var legacyTab = TabId(spaces[1]!, 2);
        Guid captured = Guid.NewGuid(), older = Guid.NewGuid();
        var group = Guid.NewGuid();
        JsonObject Wrapped(Guid id) => SwiftId(id);
        var records = new JsonArray(
            new JsonObject {
                ["id"] = Wrapped(older),
                ["selectedSpaceID"] = Wrapped(first),
                ["selectedTabIDsBySpace"] = new JsonArray(Wrapped(first), Wrapped(TabId(spaces[0]!, 1)))
            },
            new JsonObject {
                ["id"] = Wrapped(captured),
                ["selectedSpaceID"] = Wrapped(second),
                ["selectedTabIDsBySpace"] = new JsonArray(Wrapped(first), Wrapped(TabId(spaces[0]!, 4))),
                ["capturedSpaceIDs"] = new JsonArray(Wrapped(first), Wrapped(second)),
                ["sidebarWidth"] = 277.5,
                ["sidebarIsPresented"] = false,
                ["splitColumnFractionsByGroup"] = new JsonArray(Wrapped(group), new JsonArray(0.25, 0.75))
            });
        {
            var (app, _, _) = DeviceApp(directory, core);
            using var disposal = app;
            var adopted = Assert.IsType<WindowRecordsAdopted>(Assert.Single(app.Send(new AdoptWindowRecords(Bytes(records)))));
            Assert.Equal([new WindowLayout(older, null, null), new WindowLayout(captured, 277.5, false)], adopted.Layouts);
            Assert.Empty(app.Send(new AdoptWindowRecords(Bytes(records))));
        }
        var (relaunched, workspace, _) = DeviceApp(directory, core);
        using var relaunchedDisposal = relaunched;
        Assert.Empty(relaunched.Send(new AdoptWindowRecords(Bytes(records))));
        // A record that remembered its Spaces shows nothing where it chose nothing.
        var capturedWindow = Shown(relaunched.Send(new OpenWindow(captured, workspace, true, null, null, true)));
        Assert.Equal(second, capturedWindow.ShownSpaceId);
        Assert.Null(ShownTab(capturedWindow, second));
        Assert.Contains(capturedWindow.ShownTabs, tab => tab.SpaceId == second);
        // An older record takes the tab the release kept in the session.
        var olderWindow = Shown(relaunched.Send(new OpenWindow(older, workspace, true, null, null, true)));
        Assert.Equal(first, olderWindow.ShownSpaceId);
        Assert.Equal(legacyTab, ShownTab(olderWindow, second));
    }

    [Fact]
    public void ADraggedTabMayLeaveOnlyAloneFromAnUnchangedSpace() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, false, null, null, true));
        var (space, profile, tab) = (SpaceId(spaces[0]!), Guid.Parse(spaces[0]!["profile"]!["id"]!.GetValue<string>()), TabId(spaces[0]!, 0));
        Assert.Equal(new TearOffPermission(true, null), app.Query(new CanTearOff(window, space, profile, tab, null)));
        Assert.Equal(new TearOffPermission(true, null), app.Query(new CanTearOff(window, space, profile, tab, [tab])));
        Assert.Equal(TearOffRefusal.SeveralTabs, app.Query(new CanTearOff(window, space, profile, tab, [tab, TabId(spaces[0]!, 1)])).Reason);
        Assert.Equal(TearOffRefusal.SpaceChanged, app.Query(new CanTearOff(window, space, Guid.NewGuid(), tab, null)).Reason);
        Assert.Equal(TearOffRefusal.TabGone, app.Query(new CanTearOff(window, space, profile, Guid.NewGuid(), null)).Reason);
    }
}
