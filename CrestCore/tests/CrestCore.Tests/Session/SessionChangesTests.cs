using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The session change feed: every accepted state reaches a reader as the
/// changes that take it from the state before, derived by comparing the two,
/// so a reader that applies them by the rules each change documents holds the
/// core's state, and applying a batch twice changes nothing.
public sealed partial class BrowserContractsTests {
    /// Applies the session changes of one workspace the way a platform's read
    /// model does, by the rules each change record documents.
    private sealed class SessionReader(Guid workspace, SessionState opened) {
        public SessionState State { get; private set; } = opened;

        /// A reader of the workspace a batch opens.
        public static SessionReader Opening(IEnumerable<Change> changes) {
            var opened = Assert.Single(changes.OfType<WorkspaceOpened>());
            return new(opened.WorkspaceId, opened.Session);
        }

        public void Apply(IEnumerable<Change> changes) {
            foreach (var change in changes) Apply(change);
        }

        private void Apply(Change change) {
            switch (change) {
                case WorkspaceOpened opened when opened.WorkspaceId == workspace:
                    State = opened.Session;
                    break;
                case SpacesChanged spaces when spaces.WorkspaceId == workspace:
                    var kept = State.Spaces.Where(space => !spaces.Removed.Contains(space.Id)).ToList();
                    foreach (var added in spaces.Added) Upsert(kept, added, space => space.Id);
                    State = State with { Spaces = Ordered(kept, spaces.Order, space => space.Id) };
                    break;
                case SpaceSettingsChanged settings when settings.WorkspaceId == workspace:
                    Edit(settings.SpaceId, space => space with { Settings = settings.Settings });
                    break;
                case TabsChanged tabs when tabs.WorkspaceId == workspace:
                    Edit(tabs.SpaceId, space => space with {
                        Tabs = Rows(space.Tabs, tabs.Updated, tabs.Removed, tabs.Order, tab => tab.Id, recordedFirst: false)
                    });
                    break;
                case FoldersChanged folders when folders.WorkspaceId == workspace:
                    Edit(folders.SpaceId, space => space with {
                        Folders = Rows(space.Folders, folders.Updated, folders.Removed, folders.Order, folder => folder.Id, recordedFirst: false)
                    });
                    break;
                case SplitGroupsChanged groups when groups.WorkspaceId == workspace:
                    Edit(groups.SpaceId, space => space with { SplitGroups = groups.Groups });
                    break;
                case ArchiveChanged archive when archive.WorkspaceId == workspace:
                    Edit(archive.SpaceId, space => space with {
                        ArchivedTabs = Rows(space.ArchivedTabs, archive.Archived, archive.Removed, archive.Order, archived => archived.Tab.Id,
                            recordedFirst: false)
                    });
                    break;
                case HistoryChanged history when history.WorkspaceId == workspace:
                    Edit(history.SpaceId, space => space with {
                        History = Rows(space.History, history.Recorded, history.Removed, history.Order, entry => entry.Id, recordedFirst: true)
                    });
                    break;
                case WorkspaceChanged changed when changed.WorkspaceId == workspace:
                    State = State with {
                        DefaultSpaceId = changed.DefaultSpaceId,
                        DisposableSeedMarker = changed.IsDisposableSeed ? State.DisposableSeedMarker ?? Guid.NewGuid() : null,
                        SpaceDeletions = changed.SpaceDeletions
                    };
                    break;
                case AppPreferencesChanged preferences when preferences.WorkspaceId == workspace:
                    State = State with { AppPreferences = preferences.Preferences };
                    break;
            }
        }

        private void Edit(Guid spaceId, Func<SpaceState, SpaceState> edit) =>
            State = State with { Spaces = [.. State.Spaces.Select(space => space.Id == spaceId ? edit(space) : space)] };

        private static IReadOnlyList<T> Rows<T>(IReadOnlyList<T> rows, IReadOnlyList<T> updated, IReadOnlyList<Guid> removed,
            IReadOnlyList<Guid>? order, Func<T, Guid> identity, bool recordedFirst) {
            var kept = rows.Where(row => !removed.Contains(identity(row))).ToList();
            if (recordedFirst) {
                var recorded = updated.Select(identity).ToHashSet();
                kept.RemoveAll(row => recorded.Contains(identity(row)));
                kept.InsertRange(0, updated);
            } else {
                foreach (var row in updated) Upsert(kept, row, identity);
            }
            return Ordered(kept, order, identity);
        }

        private static void Upsert<T>(List<T> rows, T row, Func<T, Guid> identity) {
            var index = rows.FindIndex(existing => identity(existing) == identity(row));
            if (index >= 0) rows[index] = row;
            else rows.Add(row);
        }

        private static IReadOnlyList<T> Ordered<T>(List<T> rows, IReadOnlyList<Guid>? order, Func<T, Guid> identity) {
            if (order is null) return rows;
            var byId = rows.ToDictionary(identity);
            Assert.Equal(byId.Count, order.Count);
            return [.. order.Select(id => byId[id])];
        }
    }

    private static NativeSessionAuthority MaximalSession() {
        var creation = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Session", "Fixtures",
            "maximal-session.json")))!.AsObject();
        creation["coreWorkspaceKind"] = "persistent";
        return new NativeSessionAuthority(Bytes(creation));
    }

    /// Every command the recorded script runs, from the windows it names,
    /// reaches a reader that started from the opened workspace as changes
    /// that reproduce the core's state after each commit; applying each batch
    /// again changes nothing.
    [Fact]
    public void AReaderOfTheChangesHoldsTheCoresStateAfterEveryCommand() {
        var authority = MaximalSession();
        var clock = new TestClock(DateTimeOffset.UnixEpoch);
        using var app = new CrestApp(new AppConfiguration(null), clock, new TestIds());
        var workspace = app.AttachWorkspace(authority);
        var reader = SessionReader.Opening(app.Drain());
        Assert.Equal(authority.Current, reader.State);
        var published = new HashSet<Type>();
        foreach (var step in JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Session", "Fixtures",
            "session-commands.json")))!["commands"]!.AsArray()) {
            var request = step!["request"]!.DeepClone().AsObject();
            Guid? window = null;
            if (step["window"] is { } shown) {
                window = Guid.NewGuid();
                reader.Apply(app.Send(new OpenWindow(window.Value, workspace, Saved: false, CopyingWindowId: null,
                    shown["spaceId"] is { } space ? Guid.Parse(space.GetValue<string>()) : null,
                    [.. shown["tabs"]!.AsArray().Select(tab => new ShownTab(Guid.Parse(tab!["spaceId"]!.GetValue<string>()),
                        tab["tabId"] is { } id ? Guid.Parse(id.GetValue<string>()) : null))],
                    RestoresTabs: true)));
                request["windowId"] = window.ToString();
            }
            IReadOnlyList<Change> changes;
            if (RecordedIntents.Typed(request, workspace, window) is { } intent) {
                clock.Now = RecordedIntents.Time(request);
                changes = app.Send(intent);
            } else {
                var command = authority.PrepareCommand(Bytes(request));
                if (step["commit"]!.GetValue<bool>()) command.Commit();
                changes = app.Drain();
            }
            published.UnionWith(changes.Select(change => change.GetType()));
            reader.Apply(changes);
            Assert.Equal(authority.Current, reader.State);
            reader.Apply(changes);
            Assert.Equal(authority.Current, reader.State);
            if (window is { } opened) app.Send(new CloseWindow(opened));
        }
        Assert.Superset(new HashSet<Type> {
            typeof(SpacesChanged), typeof(SpaceSettingsChanged), typeof(TabsChanged), typeof(FoldersChanged),
            typeof(SplitGroupsChanged), typeof(HistoryChanged), typeof(ArchiveChanged), typeof(WorkspaceChanged),
            typeof(AppPreferencesChanged), typeof(TabCopied)
        }, published);
    }

    [Fact]
    public void AStateThatDidNotChangeAndSpacesAnEditKeptPublishNothing() {
        var authority = MaximalSession();
        var session = authority.Current;
        var workspace = Guid.NewGuid();
        Assert.Empty(SessionChanges.Publish(workspace, session, session));
        // Equal states that are other objects publish nothing either.
        Assert.Empty(SessionChanges.Publish(workspace, session, MaximalSession().Current));
        Assert.Empty(SessionChanges.Publish(workspace, session, session with { Spaces = [.. session.Spaces] }));

        var first = session.Spaces[0];
        var renamed = first with { Tabs = [first.Tabs[0] with { CustomTitle = "Renamed" }, .. first.Tabs.Skip(1)] };
        var tabs = Assert.IsType<TabsChanged>(Assert.Single(SessionChanges.Publish(workspace, session,
            session with { Spaces = [renamed, .. session.Spaces.Skip(1)] })));
        Assert.Equal((workspace, first.Id), (tabs.WorkspaceId, tabs.SpaceId));
        Assert.Equal([renamed.Tabs[0]], tabs.Updated);
        Assert.Empty(tabs.Removed);
        Assert.Null(tabs.Order);
    }

    [Fact]
    public void RecordsArriveByIdentityWithAnOrderOnlyWhenTheirPlacementDoesNotGiveIt() {
        var session = MaximalSession().Current;
        var workspace = Guid.NewGuid();
        var space = session.Spaces.First(space => space.History.Count > 1 && space.ArchivedTabs.Count > 1);
        IReadOnlyList<Change> Edited(SpaceState edited) =>
            SessionChanges.Publish(workspace, session, session with { Spaces = [.. session.Spaces.Select(item => item.Id == edited.Id ? edited : item)] });

        // A visit to an address the history holds moves its entry to the front.
        var visited = space.History[^1] with { Title = "Visited again", VisitCount = space.History[^1].VisitCount + 1 };
        var history = Assert.IsType<HistoryChanged>(Assert.Single(Edited(space with { History = [visited, .. space.History.SkipLast(1)] })));
        Assert.Equal([visited], history.Recorded);
        Assert.Empty(history.Removed);
        Assert.Null(history.Order);

        // An archived tab leaves by its identity, and a newly archived one goes last.
        var restored = space.ArchivedTabs[0];
        var archivedNow = space.ArchivedTabs[1] with { Tab = space.Tabs[0] with { Id = Guid.NewGuid() } };
        var archive = Assert.IsType<ArchiveChanged>(Assert.Single(Edited(space with {
            ArchivedTabs = [.. space.ArchivedTabs.Skip(1), archivedNow]
        })));
        Assert.Equal([restored.Tab.Id], archive.Removed);
        Assert.Equal([archivedNow], archive.Archived);
        Assert.Null(archive.Order);

        // Moving a tab changes no tab, so only the order arrives.
        var moved = Assert.IsType<TabsChanged>(Assert.Single(Edited(space with { Tabs = [.. space.Tabs.Skip(1), space.Tabs[0]] })));
        Assert.Empty(moved.Updated);
        Assert.Equal([.. space.Tabs.Skip(1).Select(tab => tab.Id), space.Tabs[0].Id], moved.Order);
    }

    /// A tab a window opens: the command's changes wait in the pending batch,
    /// and the next intent answers them before its own, so a reader shows the
    /// new tab before the window that shows it and ends in the core's state.
    [Fact]
    public void AnIntentAnswersThePendingBatchBeforeItsOwnChanges() {
        var authority = MaximalSession();
        using var app = new CrestApp();
        var workspace = app.AttachWorkspace(authority);
        var reader = SessionReader.Opening(app.Drain());
        var space = authority.Current.Spaces[0];
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, CopyingWindowId: null, space.Id, [new(space.Id, space.Tabs[0].Id)],
            RestoresTabs: true));
        var opened = Guid.NewGuid();
        authority.PrepareCommand(SpaceCommand(StoredSessionCodec.Encode(authority.Current), "tab.open", new() {
            ["select"] = true,
            ["tab"] = new JsonObject {
                ["id"] = SwiftId(opened),
                ["title"] = "Opened",
                ["url"] = "https://opened.example/",
                ["placement"] = "current",
                ["symbol"] = "globe",
                ["lastActivatedAt"] = 800000001.0
            }
        }, window: window)).Commit();

        var answered = app.Send(new ShowTab(window, space.Id, space.Tabs[0].Id));

        Assert.Equal([typeof(TabsChanged), typeof(WindowChanged), typeof(TabsChanged), typeof(WindowChanged)],
            answered.Select(change => change.GetType()));
        Assert.Contains(((TabsChanged)answered[0]).Updated, tab => tab.Id == opened);
        Assert.Equal(opened, ((WindowChanged)answered[1]).Window.ShownTabs.Single(tab => tab.SpaceId == space.Id).TabId);
        Assert.Equal(space.Tabs[0].Id, Assert.Single(((TabsChanged)answered[2]).Updated).Id);
        Assert.Equal(space.Tabs[0].Id, ((WindowChanged)answered[3]).Window.ShownTabs.Single(tab => tab.SpaceId == space.Id).TabId);
        reader.Apply(answered);
        Assert.Equal(authority.Current, reader.State);
        Assert.Contains(reader.State.Spaces[0].Tabs, tab => tab.Id == opened);
    }

    /// Showing a tab records its use as a change of its own, so a command
    /// prepared before it no longer describes the session and is refused,
    /// while one prepared after it commits.
    [Fact]
    public void ACommandPreparedBeforeATabWasShownIsStaleAndOnePreparedAfterCommits() {
        var authority = MaximalSession();
        using var app = new CrestApp();
        var workspace = app.AttachWorkspace(authority);
        var space = authority.Current.Spaces[0];
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, CopyingWindowId: null, space.Id, [], RestoresTabs: true));
        byte[] Rename(string title) => SpaceCommand(StoredSessionCodec.Encode(authority.Current), "tab.rename",
            new() { ["tabId"] = space.Tabs[0].Id.ToString(), ["title"] = title });
        var before = authority.PrepareCommand(Rename("Before"));
        var touched = app.Send(new ShowTab(window, space.Id, space.Tabs[1].Id));
        Assert.Single(touched.OfType<TabsChanged>());

        AssertStale(before.Commit);
        authority.PrepareCommand(Rename("After")).Commit();
        Assert.Equal("After", authority.Current.Spaces[0].Tabs[0].CustomTitle);
    }
}
