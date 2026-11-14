using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What two devices show when a Group changes on both, and what a folder
/// written before Groups looks like once this build writes it.
public sealed partial class BrowserContractsTests {
    #region Actions - Tests

    /// Only a Group carries the group mark, in its record and in the stored
    /// session, so every folder writes exactly what it wrote before Groups.
    [Fact]
    public void OnlyAGroupWritesTheGroupMark() {
        var (space, folder, group) = (Fixed(1_300), Fixed(1_301), Fixed(1_302));
        var session = SessionOf(SpaceOf(space, Fixed(1_303), folders: [FolderOf(folder, "Plain", location: "current"), GroupOf(group)],
            tabs: [TabOf(Fixed(1_304), folder: folder), TabOf(Fixed(1_305), folder: group)]));
        var journal = new JournalUnderTest(Fixed(1_306));

        journal.Stage(session);

        Assert.False(journal.Value(SyncRecordKind.Folder, folder)!.ContainsKey("isGroup"));
        Assert.True(journal.Value(SyncRecordKind.Folder, group)!["isGroup"]!.GetValue<bool>());
        var stored = SpaceIn(journal.Materialize(session), space)!["folders"]!.AsArray()
            .ToDictionary(item => StoredSessionCodec.Identity(item!["id"]), item => item!.AsObject());
        Assert.False(stored[folder].ContainsKey("isGroup"));
        Assert.True(stored[group]["isGroup"]!.GetValue<bool>());
    }

    /// One device moves a Group's last tab out, which marks the Group emptied,
    /// while another files a second tab into it. The Group stays on both with
    /// that tab, and the device holding the tab clears the mark.
    [Fact]
    public void AGroupEmptiedOnOneDeviceWhileAnotherFiledATabInItStaysWithThatTab() {
        var (space, group, held, filed) = (Fixed(1_310), Fixed(1_311), Fixed(1_312), Fixed(1_313));
        var (_, emptying, filing) = TripDevices(space, group, held, filed, 1_314);
        var emptied = TripSession(space, group, held, filed, heldInGroup: false, filedInGroup: false, keepsGroup: false);
        emptying.Stage(emptied, SyncDeletionReason.ExplicitDelete, at: 600, group);
        Assert.NotNull(emptying.Value(SyncRecordKind.Folder, group)!["emptiedAt"]);
        using var device = new SyncingDevice(
            TripSession(space, group, held, filed, heldInGroup: true, filedInGroup: true, keepsGroup: true), filing);
        Assert.Contains(Name(SyncRecordKind.Tab, filed), device.Journal.Pending);

        var here = SpaceIn(device.Merge(Pending(emptying)), space)!;
        Assert.Null(device.Journal.Value(SyncRecordKind.Folder, group)!["emptiedAt"]);
        Assert.Contains(Name(SyncRecordKind.Folder, group), device.Journal.Pending);
        emptying.Merge(Pending(device.Journal));
        var there = SpaceIn(emptying.Materialize(emptied), space)!;

        foreach (var side in new[] { here, there }) {
            var kept = StoredSessionCodec.DecodeFolder(Assert.Single(side["folders"]!.AsArray())!);
            Assert.Equal((group, true), (kept.Id, kept.IsGroup));
            var tabs = side["tabs"]!.AsArray().ToDictionary(tab => StoredSessionCodec.Identity(tab!["id"]), tab => tab!);
            Assert.Null(tabs[held]["folderID"]);
            Assert.Equal(group, StoredSessionCodec.Identity(tabs[filed]["folderID"]));
        }
    }

    /// A device that hears of a Group's mark before the tab another device
    /// filed in it leaves the Group out until the tab arrives, then shows it
    /// with the tab and clears the mark.
    [Fact]
    public void AGroupMarkedEmptiedShowsAgainOnceATabFiledInItArrives() {
        var (space, group, held, filed) = (Fixed(1_370), Fixed(1_371), Fixed(1_372), Fixed(1_373));
        var (cloud, emptying, filing) = TripDevices(space, group, held, filed, 1_374);
        emptying.Stage(TripSession(space, group, held, filed, heldInGroup: false, filedInGroup: false, keepsGroup: false),
            SyncDeletionReason.ExplicitDelete, at: 600, group);
        filing.Stage(TripSession(space, group, held, filed, heldInGroup: true, filedInGroup: true, keepsGroup: true), at: 610);
        using var device = new SyncingDevice(cloud, Fixed(1_377));

        Assert.Empty(SpaceIn(device.Merge(Pending(emptying)), space)!["folders"]!.AsArray());
        Assert.NotNull(device.Journal.Value(SyncRecordKind.Folder, group)!["emptiedAt"]);
        var arrived = SpaceIn(device.Merge(Pending(filing)), space)!;

        Assert.Equal(group, StoredSessionCodec.DecodeFolder(Assert.Single(arrived["folders"]!.AsArray())!).Id);
        Assert.Contains(arrived["tabs"]!.AsArray(), tab => StoredSessionCodec.Identity(tab!["id"]) == filed
            && StoredSessionCodec.Identity(tab["folderID"]) == group);
        Assert.Null(device.Journal.Value(SyncRecordKind.Folder, group)!["emptiedAt"]);
    }

    /// A plain folder of the open tabs that one device empties stays out of
    /// sight on a device that receives the mark, and on the emptying device
    /// itself once it next takes in records from the cloud.
    [Fact]
    public void APlainFolderAnEditEmptiedStaysOutOfSightWhereItHoldsNothing() {
        var (space, folder, held, loose) = (Fixed(1_450), Fixed(1_451), Fixed(1_452), Fixed(1_453));
        var start = SessionOf(SpaceOf(space, Fixed(1_398), "Trip", "airplane", folders: [FolderOf(folder, "Plain", location: "current")], tabs: [
            TabOf(Fixed(1_397), "Pinned", "https://example.com/pinned", placement: "pinned", activated: 500),
            TabOf(held, "Inside", "https://example.com/inside", folder: folder, activated: 500),
            TabOf(loose, "Loose", "https://example.com/loose", activated: 500)
        ]));
        var merged = CloudHolding(start, 1_454);
        using var emptying = new SyncingDevice(start, merged(1_455));
        using var receiving = new SyncingDevice(start, merged(1_456));

        emptying.Edit(workspace => new MoveTab(workspace, space, held, TabPlacement.Current, null, null, LeavesSplit: false));
        Assert.NotNull(emptying.Journal.Value(SyncRecordKind.Folder, folder)!["emptiedAt"]);
        Settle(emptying, receiving);
        var renamed = SessionOf(SpaceOf(space, Fixed(1_398), "Trip", "airplane", tabs: [
            TabOf(Fixed(1_397), "Pinned", "https://example.com/pinned", placement: "pinned", activated: 500),
            TabOf(held, "Inside", "https://example.com/inside", activated: 500, positioned: 900),
            TabOf(loose, "Renamed", "https://example.com/loose", activated: 500)
        ]));
        var other = merged(1_457);
        other.Merge(emptying.Journal.Records);
        other.Stage(renamed, at: 900);
        emptying.Merge(Pending(other).Where(record => RecordName(record["id"]!) == Name(SyncRecordKind.Tab, loose)));

        foreach (var device in new[] { emptying, receiving })
            Assert.Empty(SpaceIn(device.Session, space)!["folders"]!.AsArray());
    }

    /// One device deletes the folder inside a folder of the open tabs, which
    /// empties and marks the outer one, while another files a tab into the
    /// inner one. A device holding both shows the outer folder with that tab
    /// moved up into it, as the inner one's deletion moves it.
    [Fact]
    public void ATabInADeletedFolderKeepsTheMarkedFolderAroundIt() {
        var (space, outer, inner, tab) = (Fixed(1_440), Fixed(1_441), Fixed(1_442), Fixed(1_443));
        JsonObject Session(bool keepsFolders, Guid? tabIn) {
            List<JsonObject> folders = keepsFolders
                ? [FolderOf(outer, "Outer", location: "current"), FolderOf(inner, "Inner", parent: outer, location: "current")] : [];
            List<JsonObject> tabs = [TabOf(Fixed(1_397), "Pinned", "https://example.com/pinned", placement: "pinned", activated: 500)];
            if (tabIn is { } folder) tabs.Add(TabOf(tab, "Filed", "https://example.com/filed", folder: folder, activated: 500, positioned: 610));
            return SessionOf(SpaceOf(space, Fixed(1_398), "Trip", "airplane", folders: folders, tabs: tabs));
        }
        var start = Session(keepsFolders: true, tabIn: null);
        var merged = CloudHolding(start, 1_444);
        var (deleting, filing, holding) = (merged(1_445), merged(1_446), merged(1_447));
        deleting.Stage(Session(keepsFolders: false, tabIn: null), SyncDeletionReason.ExplicitDelete, at: 600, outer);
        filing.Stage(Session(keepsFolders: true, tabIn: inner), at: 610);
        holding.Merge(Pending(deleting));
        holding.Merge(Pending(filing));
        Assert.NotNull(holding.Value(SyncRecordKind.Folder, outer)!["emptiedAt"]);
        Assert.NotNull(holding.Record(SyncRecordKind.Folder, inner)!["tombstone"]);

        var shown = SpaceIn(holding.Materialize(start), space)!;
        Assert.Contains(shown["folders"]!.AsArray(), folder => StoredSessionCodec.Identity(folder!["id"]) == outer);
        Assert.Contains(shown["tabs"]!.AsArray(),
            item => StoredSessionCodec.Identity(item!["id"]) == tab && StoredSessionCodec.Identity(item["folderID"]) == outer);
    }

    /// A device that knows no emptied mark keeps it on a Group's record when
    /// it writes the Group, as it keeps any member it does not know. Its rename
    /// arrives here with the mark, so the Group stays out of sight while it
    /// holds nothing, and shows renamed once a tab sits in it.
    [Fact]
    public void AnOlderDevicesWriteOfAMarkedGroupKeepsItOutOfSight() {
        var (space, group, held, filed) = (Fixed(1_380), Fixed(1_381), Fixed(1_382), Fixed(1_383));
        var (_, emptying, older) = TripDevices(space, group, held, filed, 1_384);
        var emptied = TripSession(space, group, held, filed, heldInGroup: false, filedInGroup: false, keepsGroup: false);
        emptying.Stage(emptied, SyncDeletionReason.ExplicitDelete, at: 600, group);
        older.Merge(Pending(emptying));
        var renamed = older.Record(SyncRecordKind.Folder, group)!.DeepClone().AsObject();
        renamed["payload"]!["value"]!["title"] = "Lisbon";
        renamed["version"] = new JsonObject { ["logicalClock"] = older.Clock + 1, ["deviceID"] = Fixed(1_386).ToString("D").ToUpperInvariant() };
        Assert.NotNull(renamed["payload"]!["value"]!["emptiedAt"]);

        emptying.Merge(renamed);
        Assert.Empty(SpaceIn(emptying.Materialize(emptied), space)!["folders"]!.AsArray());

        var filedThere = TripSession(space, group, held, filed, heldInGroup: false, filedInGroup: true, keepsGroup: true);
        FirstSpace(filedThere)["folders"]![0]!["title"] = "Lisbon";
        older.Stage(filedThere, at: 700);
        emptying.Merge(Pending(older).Where(record => RecordName(record["id"]!) == Name(SyncRecordKind.Tab, filed)));
        var shown = StoredSessionCodec.DecodeFolder(Assert.Single(SpaceIn(emptying.Materialize(emptied), space)!["folders"]!.AsArray())!);
        Assert.Equal((group, "Lisbon", true), (shown.Id, shown.Title, shown.IsGroup));
    }

    /// A device that knows no Groups moves a Group's last tab out and keeps the
    /// Group, as it keeps any folder, while this device has filed a second tab
    /// into it. The Group still holds a tab here, so it stays a Group.
    [Fact]
    public void AGroupAnOlderDeviceEmptiedStaysWhileThisDeviceFiledATabInIt() {
        var (space, group, held, filed) = (Fixed(1_320), Fixed(1_321), Fixed(1_322), Fixed(1_323));
        var (_, older, filing) = TripDevices(space, group, held, filed, 1_324);
        older.Stage(TripSession(space, group, held, filed, heldInGroup: false, filedInGroup: false, keepsGroup: true), at: 600);
        using var device = new SyncingDevice(
            TripSession(space, group, held, filed, heldInGroup: true, filedInGroup: true, keepsGroup: true), filing);

        var here = SpaceIn(device.Merge(Pending(older)), space)!;

        var kept = StoredSessionCodec.DecodeFolder(Assert.Single(here["folders"]!.AsArray())!);
        Assert.Equal(group, kept.Id);
        Assert.True(kept.IsGroup);
        var tabs = here["tabs"]!.AsArray().ToDictionary(tab => StoredSessionCodec.Identity(tab!["id"]), tab => tab!);
        Assert.Null(tabs[held]["folderID"]);
        Assert.Equal(group, StoredSessionCodec.Identity(tabs[filed]["folderID"]));
        Assert.NotNull(device.Journal.Value(SyncRecordKind.Folder, group));
    }

    /// One device turns a Group into a folder while another renames it. A
    /// folder's record merges as a whole, so one edit wins and the other is
    /// lost, the same on both devices.
    [Fact]
    public void AGroupTurnedIntoAFolderOnOneDeviceAndRenamedOnAnotherEndsTheSameOnBoth() {
        var (space, group, held, filed) = (Fixed(1_330), Fixed(1_331), Fixed(1_332), Fixed(1_333));
        var (cloud, converting, renaming) = TripDevices(space, group, held, filed, 1_334);
        var converted = TripSession(space, group, held, filed, heldInGroup: true, filedInGroup: false, keepsGroup: true);
        FirstSpace(converted)["folders"]![0]!.AsObject().Remove("isGroup");
        converting.Stage(converted, at: 600);
        var renamed = TripSession(space, group, held, filed, heldInGroup: true, filedInGroup: false, keepsGroup: true);
        FirstSpace(renamed)["folders"]![0]!["title"] = "Lisbon";
        renaming.Stage(renamed, at: 610);

        var (fromConverting, fromRenaming) = (Pending(converting), Pending(renaming));
        converting.Merge(fromRenaming);
        renaming.Merge(fromConverting);

        var first = StoredSessionCodec.DecodeFolder(Assert.Single(SpaceIn(converting.Materialize(cloud), space)!["folders"]!.AsArray())!);
        var second = StoredSessionCodec.DecodeFolder(Assert.Single(SpaceIn(renaming.Materialize(cloud), space)!["folders"]!.AsArray())!);
        Assert.Equal((first.IsGroup, first.Title), (second.IsGroup, second.Title));
        Assert.Contains((first.IsGroup, first.Title), new[] { (false, "Trip"), (true, "Lisbon") });
    }


    /// A device opened after a long gap sweeps its stale open tabs out of a
    /// Group another device showed them in ten minutes earlier. A tab shown
    /// before a sweep and the sweep's removal are decided by version, as on
    /// main, and here the stale device's removal is the newer, so the tabs go
    /// to the archive on both devices. The Group goes with them, out of sight
    /// on both, and its record stays, marked emptied, never deleted.
    [Fact]
    public void AStaleDevicesSweepArchivesTabsShownBeforeItAndTheGroupGoesWithThem() {
        var (space, group, first, second) = (Fixed(1_340), Fixed(1_341), Fixed(1_342), Fixed(1_343));
        var stale = GroupedSession(space, group, [first, second], [], activated: 500);
        var merged = CloudHolding(stale, 1_344);
        var shownBefore = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 600;
        using var inUse = new SyncingDevice(GroupedSession(space, group, [first, second], [], activated: shownBefore), merged(1_345));
        using var sweeping = new SyncingDevice(stale, ClockAhead(merged(1_346), by: 100));

        sweeping.Edit(workspace => new CleanUpCurrentTabs(workspace, space));
        Settle(inUse, sweeping);

        foreach (var device in new[] { inUse, sweeping }) {
            var kept = SpaceIn(device.Session, space)!;
            Assert.Empty(kept["folders"]!.AsArray());
            Assert.DoesNotContain(kept["tabs"]!.AsArray(), tab => StoredSessionCodec.Identity(tab!["id"]) is var id && (id == first || id == second));
            var archived = kept["archivedTabs"]!.AsArray().Select(item => StoredSessionCodec.Identity(item!["tab"]!["id"])).ToHashSet();
            Assert.Contains(first, archived);
            Assert.Contains(second, archived);
            Assert.NotNull(device.Journal.Value(SyncRecordKind.Folder, group)!["emptiedAt"]);
        }
    }

    /// A device opened after a long gap sweeps its stale open tabs out of a
    /// Group another device shows them in a minute later, before the sweep
    /// arrives there. A tab shown after a removal stays, so the Group stays on
    /// both devices with its tabs, and the device that kept them clears the
    /// mark.
    [Fact]
    public void AStaleDevicesSweepLeavesAGroupWhoseTabsWereShownAfterIt() {
        var (space, group, first, second) = (Fixed(1_345), Fixed(1_346), Fixed(1_347), Fixed(1_348));
        var stale = GroupedSession(space, group, [first, second], [], activated: 500);
        var merged = CloudHolding(stale, 1_349);
        var shownAfter = DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 60;
        using var inUse = new SyncingDevice(GroupedSession(space, group, [first, second], [], activated: shownAfter), merged(1_400));
        using var sweeping = new SyncingDevice(stale, ClockAhead(merged(1_401), by: 100));

        sweeping.Edit(workspace => new CleanUpCurrentTabs(workspace, space));
        Assert.Empty(SpaceIn(sweeping.Session, space)!["folders"]!.AsArray());
        Settle(inUse, sweeping);

        foreach (var (side, device) in new[] { ("in use", inUse), ("swept", sweeping) }) {
            AssertGroupHolds(side, SpaceIn(device.Session, space)!, group, [first, second]);
            Assert.Null(device.Journal.Value(SyncRecordKind.Folder, group)!["emptiedAt"]);
        }
    }

    /// Moving a Group's last tab out, an edit that otherwise stages once edits
    /// pause, writes the Group's mark to disk with the edit's own save, so a
    /// crash right after it can't leave the Group's record unmarked.
    [Fact]
    public void AGroupAnEditEmptiesIsMarkedOnDiskWithTheEditsSave() {
        var (space, group, held, loose) = (Fixed(1_410), Fixed(1_411), Fixed(1_412), Fixed(1_413));
        var start = GroupedSession(space, group, [held], [loose], activated: 500);
        using var device = new SyncingDevice(start, CloudHolding(start, 1_414)(1_415));

        device.Send(workspace => new MoveTab(workspace, space, held, TabPlacement.Current, null, null, LeavesSplit: false));

        Assert.Empty(device.StoredSession["spaces"]![0]!["folders"]!.AsArray());
        var record = device.StoredJournal["records"]!.AsArray().Single(item => RecordName(item!["id"]!) == Name(SyncRecordKind.Folder, group))!;
        Assert.NotNull(record["payload"]!["value"]!["emptiedAt"]);
    }

    /// A folder one device empties stays out of sight there, though another
    /// device still shows it for a Start Page of its own, which never syncs:
    /// that device keeps the mark rather than writing the folder back.
    [Fact]
    public void AFolderShownElsewhereOnlyForATabThatNeverSyncsStaysMarked() {
        var (space, folder, held, page) = (Fixed(1_420), Fixed(1_421), Fixed(1_422), Fixed(1_423));
        JsonObject Session(bool holdsPage) {
            List<JsonObject> tabs = [
                TabOf(Fixed(1_397), "Pinned", "https://example.com/pinned", placement: "pinned", activated: 500),
                TabOf(held, "Inside", "https://example.com/inside", folder: folder, activated: 500)
            ];
            if (holdsPage) tabs.Add(TabOf(page, "Start Page", url: null, symbol: "flag.fill", folder: folder, activated: 500));
            return SessionOf(SpaceOf(space, Fixed(1_398), "Trip", "airplane", folders: [FolderOf(folder, "Plain", location: "current")],
                tabs: tabs));
        }
        var merged = CloudHolding(Session(holdsPage: false), 1_424);
        using var showing = new SyncingDevice(Session(holdsPage: true), merged(1_425));
        using var closing = new SyncingDevice(Session(holdsPage: false), merged(1_426));

        var window = closing.Open(space, held);
        closing.Edit(workspace => new CloseTabs(workspace, window, space, Picking(held)));
        Settle(showing, closing);

        Assert.Empty(SpaceIn(closing.Session, space)!["folders"]!.AsArray());
        Assert.Contains(SpaceIn(showing.Session, space)!["tabs"]!.AsArray(),
            tab => StoredSessionCodec.Identity(tab!["id"]) == page && StoredSessionCodec.Identity(tab["folderID"]) == folder);
        Assert.NotNull(showing.Journal.Value(SyncRecordKind.Folder, folder)!["emptiedAt"]);
    }

    /// One device closes the last tab it knows of in a Group while another has
    /// filed a second tab there that the first has not received. The Group
    /// still holds a tab, so both devices keep it with that tab inside.
    [Fact]
    public void AGroupClosedFromAStaleViewStaysWhereAnotherDeviceFiledATabInIt() {
        var (space, group, held, filed) = (Fixed(1_350), Fixed(1_351), Fixed(1_352), Fixed(1_353));
        var start = GroupedSession(space, group, [held], [filed], activated: 500);
        var merged = CloudHolding(start, 1_354);
        using var filing = new SyncingDevice(start, merged(1_355));
        using var closing = new SyncingDevice(start, merged(1_356));

        filing.Edit(workspace => new MoveTab(workspace, space, filed, TabPlacement.Current, group, null, LeavesSplit: false));
        var window = closing.Open(space, held);
        closing.Edit(workspace => new CloseTabs(workspace, window, space, Picking(held)));
        Assert.Empty(SpaceIn(closing.Session, space)!["folders"]!.AsArray());
        Settle(filing, closing);

        foreach (var (side, session) in new[] { ("filing", filing.Session), ("closing", closing.Session) })
            AssertGroupHolds(side, SpaceIn(session, space)!, group, [filed]);
    }
    #endregion

    #region Actions - Fixtures

    /// A Group of the current tabs in the stored format.
    private static JsonObject GroupOf(Guid id, string title = "Trip") {
        var group = FolderOf(id, title, location: "current");
        group["isGroup"] = true;
        return group;
    }

    /// A Space holding the Group `group` with `held` in it, and `filed` beside
    /// or in it, each where its flag says.
    private static JsonObject TripSession(Guid space, Guid group, Guid held, Guid filed, bool heldInGroup, bool filedInGroup,
        bool keepsGroup) => SessionOf(SpaceOf(space, Fixed(1_399), "Trip", "airplane", folders: keepsGroup ? [GroupOf(group)] : [],
        tabs: [
            TabOf(held, "Flights", "https://example.com/flights", folder: heldInGroup ? group : null, activated: 500,
                positioned: heldInGroup ? null : 600),
            TabOf(filed, "Hotels", "https://example.com/hotels", folder: filedInGroup ? group : null, activated: 501,
                positioned: filedInGroup ? 605 : null)
        ]));

    /// The cloud's copy of a trip with `held` in its Group, written by the
    /// device `seed` names, and two devices, the next two, that have merged it.
    private static (JsonObject Cloud, JournalUnderTest First, JournalUnderTest Second) TripDevices(Guid space, Guid group, Guid held,
        Guid filed, int seed) {
        var cloudSession = TripSession(space, group, held, filed, heldInGroup: true, filedInGroup: false, keepsGroup: true);
        var cloud = new JournalUnderTest(Fixed(seed));
        cloud.Stage(cloudSession, at: 500);
        var first = new JournalUnderTest(Fixed(seed + 1));
        var second = new JournalUnderTest(Fixed(seed + 2));
        first.Merge(cloud.Records);
        second.Merge(cloud.Records);
        return (cloudSession, first, second);
    }

    /// A Space where the Group `group` holds `inside`, with `outside` and a
    /// pinned tab beside it, every tab last shown `activated` seconds after 1970.
    private static JsonObject GroupedSession(Guid space, Guid group, Guid[] inside, Guid[] outside, double activated) =>
        SessionOf(SpaceOf(space, Fixed(1_398), "Trip", "airplane", folders: [GroupOf(group)], tabs: [
            TabOf(Fixed(1_397), "Pinned", "https://example.com/pinned", placement: "pinned", activated: activated),
            .. inside.Select(tab => TabOf(tab, "Inside", $"https://example.com/{tab:N}", folder: group, activated: activated)),
            .. outside.Select(tab => TabOf(tab, "Outside", $"https://example.com/{tab:N}", activated: activated))
        ]));

    /// A journal of the device numbered by its argument that has merged what
    /// the cloud holds of `session`, staged by the device `seed` names.
    private static Func<int, JournalUnderTest> CloudHolding(JsonObject session, int seed) {
        var cloud = new JournalUnderTest(Fixed(seed));
        cloud.Stage(session, at: 500);
        return device => {
            var journal = new JournalUnderTest(Fixed(device));
            journal.Merge(cloud.Records);
            journal.MarkUploaded();
            return journal;
        };
    }

    /// Trades what each device waits to upload until neither waits, as the
    /// cloud carries it, a few rounds at most.
    private static void Settle(SyncingDevice first, SyncingDevice second) {
        for (var round = 0; round < 4; round++) {
            var (fromFirst, fromSecond) = (Pending(first.Journal).ToArray(), Pending(second.Journal).ToArray());
            if (fromFirst.Length == 0 && fromSecond.Length == 0) return;
            first.MarkUploaded();
            second.MarkUploaded();
            if (fromSecond.Length > 0) first.Merge(fromSecond);
            if (fromFirst.Length > 0) second.Merge(fromFirst);
        }
        var (left, right) = (first.Journal.Pending, second.Journal.Pending);
        if (left.Count == 0 && right.Count == 0) return;
        Assert.Fail($"The devices still write after four rounds: [{string.Join(", ", left)}] and [{string.Join(", ", right)}].");
    }

    /// `journal` with its clock moved `by` past the cloud's, as a device's
    /// own edits move it, so what it stages next is newer than anything the
    /// cloud holds. The record it learns this from is one it already holds.
    private static JournalUnderTest ClockAhead(JournalUnderTest journal, int by) {
        var newer = journal.Records[0].DeepClone().AsObject();
        newer["version"] = new JsonObject { ["logicalClock"] = journal.Clock + (ulong)by, ["deviceID"] = Fixed(1_399).ToString("D").ToUpperInvariant() };
        journal.Merge(newer);
        return journal;
    }

    /// Asserts that `space`, a stored-format Space the device `side` holds,
    /// holds the Group `group` with exactly `tabs` inside it.
    private static void AssertGroupHolds(string side, JsonNode space, Guid group, Guid[] tabs) {
        var folders = space["folders"]!.AsArray().Select(item => StoredSessionCodec.DecodeFolder(item!)).ToArray();
        var held = space["tabs"]!.AsArray().Select(item => (Id: StoredSessionCodec.Identity(item!["id"]),
            Folder: item!["folderID"] is { } folder ? StoredSessionCodec.Identity(folder) : (Guid?)null)).ToArray();
        string Seen() => $"{side}: folders [{string.Join(", ", folders.Select(folder => $"{folder.Title} group={folder.IsGroup}"))}], " +
            $"tabs [{string.Join(", ", held.Select(tab => $"{tab.Id.ToString()[^4..]} in {tab.Folder?.ToString()[^4..] ?? "-"}"))}]";
        Assert.True(folders.Any(folder => folder.Id == group && folder.IsGroup), "The Group is gone. " + Seen());
        Assert.True(tabs.All(tab => held.Contains((tab, group))), "A tab is missing from the Group. " + Seen());
    }

    /// The records `journal` waits to upload.
    private static IEnumerable<JsonObject> Pending(JournalUnderTest journal) {
        var pending = journal.Pending;
        return [.. journal.Records.Where(record => pending.Contains(RecordName(record["id"]!)))];
    }

    #endregion
}
