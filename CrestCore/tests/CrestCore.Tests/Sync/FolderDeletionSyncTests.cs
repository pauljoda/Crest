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
}
