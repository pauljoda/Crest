using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What two devices keep when a folder is deleted on one while the other
/// files a tab into it.
public sealed partial class BrowserContractsTests {
    /// The person deletes a folder of the open tabs on one device, which keeps
    /// its tabs, while another device files a second tab into it. Both devices
    /// end without the folder and with both tabs at the top level.
    [Fact]
    public void AFolderDeletedWhileAnotherDeviceFiledATabInItKeepsThatTabOnBoth() {
        var (space, folder, held, filed) = (Fixed(1_390), Fixed(1_391), Fixed(1_392), Fixed(1_393));
        var start = SessionOf(SpaceOf(space, Fixed(1_398), "Trip", "airplane", folders: [FolderOf(folder, "Plain", location: "current")],
            tabs: [
                TabOf(Fixed(1_397), "Pinned", "https://example.com/pinned", placement: "pinned", activated: 500),
                TabOf(held, "Inside", "https://example.com/inside", folder: folder, activated: 500),
                TabOf(filed, "Outside", "https://example.com/outside", activated: 500)
            ]));
        var merged = CloudHolding(start, 1_394);
        using var filing = new SyncingDevice(start, merged(1_395));
        using var deleting = new SyncingDevice(start, merged(1_396));

        filing.Edit(workspace => new MoveTab(workspace, space, filed, TabPlacement.Current, folder, null, LeavesSplit: false));
        deleting.Edit(workspace => new DeleteFolder(workspace, space, folder));
        Settle(filing, deleting);

        foreach (var session in new[] { filing.Session, deleting.Session }) {
            var kept = SpaceIn(session, space)!;
            Assert.Empty(kept["folders"]!.AsArray());
            var tabs = kept["tabs"]!.AsArray().ToDictionary(tab => StoredSessionCodec.Identity(tab!["id"]), tab => tab!);
            Assert.True(tabs.ContainsKey(held) && tabs.ContainsKey(filed));
            Assert.Null(tabs[filed]["folderID"]);
        }
    }

    /// A device that hears a folder was deleted moves the tab it holds there to
    /// the top level, dated a moment after that tab's copy was placed. A move
    /// of the tab into a Group that another device made later, arriving in a
    /// later batch, still wins, and the tab lands in the Group.
    [Fact]
    public void ATabMovedOutOfADeletedFolderLosesToALaterMoveElsewhere() {
        var (space, folder, group, tab, other) = (Fixed(1_430), Fixed(1_431), Fixed(1_432), Fixed(1_433), Fixed(1_434));
        JsonObject Session(bool keepsFolder, Guid? tabIn, double? positioned) {
            List<JsonObject> folders = [GroupOf(group)];
            if (keepsFolder) folders.Insert(0, FolderOf(folder, "Plain", location: "current"));
            return SessionOf(SpaceOf(space, Fixed(1_398), "Trip", "airplane", folders: folders, tabs: [
                TabOf(Fixed(1_397), "Pinned", "https://example.com/pinned", placement: "pinned", activated: 500),
                TabOf(tab, "Moved", "https://example.com/moved", folder: tabIn, activated: 500, positioned: positioned),
                TabOf(other, "Kept", "https://example.com/kept", folder: group, activated: 500)
            ]));
        }
        var start = Session(keepsFolder: true, tabIn: folder, positioned: 600);
        var merged = CloudHolding(start, 1_435);
        var (deleting, moving) = (merged(1_436), merged(1_437));
        deleting.Stage(Session(keepsFolder: false, tabIn: null, positioned: 650), at: 650);
        moving.Stage(Session(keepsFolder: true, tabIn: group, positioned: 700), at: 700);
        using var device = new SyncingDevice(start, merged(1_438));

        device.Merge(Pending(deleting).Where(record => RecordName(record["id"]!) == Name(SyncRecordKind.Folder, folder)));
        var repaired = device.Journal.Value(SyncRecordKind.Tab, tab)!;
        Assert.Null(repaired["folderID"]);
        Assert.Equal(At(600) + 0.001, repaired["positionModifiedAt"]!.GetValue<double>(), precision: 6);

        var arrived = SpaceIn(device.Merge(Pending(moving).Where(record => RecordName(record["id"]!) == Name(SyncRecordKind.Tab, tab))), space)!;
        Assert.Contains(arrived["tabs"]!.AsArray(),
            item => StoredSessionCodec.Identity(item!["id"]) == tab && StoredSessionCodec.Identity(item["folderID"]) == group);
    }
}
