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

    /// The records `journal` waits to upload.
    private static IEnumerable<JsonObject> Pending(JournalUnderTest journal) {
        var pending = journal.Pending;
        return [.. journal.Records.Where(record => pending.Contains(RecordName(record["id"]!)))];
    }

    #endregion
}
