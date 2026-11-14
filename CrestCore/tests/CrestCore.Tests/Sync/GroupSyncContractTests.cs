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

    /// One device moves a Group's last tab out, which deletes the Group, while
    /// another files a second tab into it. Both end without the Group and with
    /// both tabs loose.
    [Fact]
    public void AGroupEmptiedOnOneDeviceWhileAnotherFiledATabInItGoesAndKeepsThatTab() {
        var (space, group, held, filed) = (Fixed(1_310), Fixed(1_311), Fixed(1_312), Fixed(1_313));
        var (cloud, emptying, filing) = TripDevices(space, group, held, filed, 1_314);
        emptying.Stage(TripSession(space, group, held, filed, heldInGroup: false, filedInGroup: false, keepsGroup: false),
            SyncDeletionReason.ExplicitDelete, at: 600);
        using var device = new SyncingDevice(
            TripSession(space, group, held, filed, heldInGroup: true, filedInGroup: true, keepsGroup: true), filing);
        Assert.Contains(Name(SyncRecordKind.Tab, filed), device.Journal.Pending);

        var here = SpaceIn(device.Merge(Pending(emptying)), space)!;
        emptying.Merge(Pending(device.Journal));
        var there = SpaceIn(emptying.Materialize(cloud), space)!;

        foreach (var side in new[] { here, there }) {
            Assert.Empty(side["folders"]!.AsArray());
            Assert.Equal([held, filed], Ids(side["tabs"]).Order());
            Assert.All(side["tabs"]!.AsArray(), tab => Assert.Null(tab!["folderID"]));
        }
        Assert.Equal("explicitDelete", device.Journal.Record(SyncRecordKind.Folder, group)!["tombstone"]!["reason"]!.GetValue<string>());
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


    /// A device opened after a long gap sweeps its stale open tabs, which
    /// empties a Group another device has shown since. The sweep is
    /// maintenance, not the person's deletion, so the Group stays on both
    /// devices with the tabs that are still in use.
    [Fact]
    public void AStaleDevicesSweepLeavesAGroupAnotherDeviceStillUses() {
        var (space, group, first, second) = (Fixed(1_340), Fixed(1_341), Fixed(1_342), Fixed(1_343));
        var stale = GroupedSession(space, group, [first, second], [], activated: 500);
        var merged = CloudHolding(stale, 1_344);
        var shownSince = DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 3_600;
        using var inUse = new SyncingDevice(GroupedSession(space, group, [first, second], [], activated: shownSince), merged(1_345));
        using var sweeping = new SyncingDevice(stale, merged(1_346));

        sweeping.Edit(workspace => new CleanUpCurrentTabs(workspace, space));
        Assert.Empty(SpaceIn(sweeping.Session, space)!["folders"]!.AsArray());
        Settle(inUse, sweeping);

        foreach (var (side, session) in new[] { ("in use", inUse.Session), ("swept", sweeping.Session) })
            AssertGroupHolds(side, SpaceIn(session, space)!, group, [first, second]);
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
