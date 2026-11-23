using CrestCore.Contracts;

using Xunit;

using SiteAction = CrestCore.Contracts.SiteControlAction;

namespace CrestCore.Tests;

/// The actions on top of Site Controls are device state: one to four, each
/// offered on the device and none twice, kept by the device store across a
/// relaunch and published at launch.
public sealed partial class BrowserContractsTests {
    private static IReadOnlyList<SiteAction> TopActions(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<SiteControlTopActionsChanged>()).TopActions.Actions;

    [Fact]
    public void TheActionsOnTopOfSiteControlsMoveComeAndGoAndSurviveARelaunch() {
        using var directory = new StorageDirectory();
        var launch = new AdoptDevicePreferences(null, null, null, null, []);
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            Assert.Equal([SiteAction.CopyLink, SiteAction.Share, SiteAction.PinTab, SiteAction.FindInPage],
                TopActions(app.Send(launch)));
            // A tile dragged along the row lands where it is let go, the
            // others making room.
            Assert.Equal([SiteAction.Share, SiteAction.PinTab, SiteAction.CopyLink, SiteAction.FindInPage],
                TopActions(app.Send(new MoveSiteControlTopAction(SiteAction.CopyLink, 2))));
            // One dragged out leaves the others; one brought in takes its
            // place among them, and a fifth lets the last go.
            Assert.Equal([SiteAction.Share, SiteAction.CopyLink, SiteAction.FindInPage],
                TopActions(app.Send(new RemoveSiteControlTopAction(SiteAction.PinTab))));
            Assert.Equal([SiteAction.CapturePage, SiteAction.Share, SiteAction.CopyLink, SiteAction.FindInPage],
                TopActions(app.Send(new MoveSiteControlTopAction(SiteAction.CapturePage, 0))));
            Assert.Equal([SiteAction.CapturePage, SiteAction.ReloadPage, SiteAction.Share, SiteAction.CopyLink],
                TopActions(app.Send(new MoveSiteControlTopAction(SiteAction.ReloadPage, 1))));
            // Choosing a slot and then an action replaces it, or trades
            // places with one already there.
            Assert.Equal([SiteAction.CapturePage, SiteAction.ReloadPage, SiteAction.Share, SiteAction.PinTab],
                TopActions(app.Send(new PlaceSiteControlTopAction(SiteAction.PinTab, 3))));
            Assert.Equal([SiteAction.Share, SiteAction.ReloadPage, SiteAction.CapturePage, SiteAction.PinTab],
                TopActions(app.Send(new PlaceSiteControlTopAction(SiteAction.Share, 0))));
        }
        {
            var (relaunched, _, _) = DeviceApp(directory);
            using var disposal = relaunched;
            Assert.Equal([SiteAction.Share, SiteAction.ReloadPage, SiteAction.CapturePage, SiteAction.PinTab],
                TopActions(relaunched.Send(launch)));
            Assert.Equal(SiteControlTopActions.Default.Actions, TopActions(relaunched.Send(new ResetSiteControlTopActions())));
        }
        var (reset, _, _) = DeviceApp(directory);
        using var resetDisposal = reset;
        Assert.Equal(SiteControlTopActions.Default.Actions, TopActions(reset.Send(launch)));
    }

    /// The last action stays, and a device never holds an action only another
    /// kind of device offers: placing one changes nothing, and one kept from
    /// elsewhere is left out.
    [Fact]
    public void TheLastActionStaysAndAnActionTheDeviceDoesNotOfferNeverSitsOnTop() {
        var single = new SiteControlTopActions([SiteAction.CopyLink]);
        Assert.Same(single, single.Removing(SiteAction.CopyLink));
        Assert.Same(SiteControlTopActions.Default,
            SiteControlTopActions.Default.Placing(SiteAction.CapturePage, 0, DevicePlatform.Mobile));
        Assert.Same(SiteControlTopActions.Default,
            SiteControlTopActions.Default.Moving(SiteAction.CapturePage, 0, DevicePlatform.Mobile));
        // And the Mac never holds one only a phone or tablet offers.
        Assert.Same(SiteControlTopActions.Default,
            SiteControlTopActions.Default.Placing(SiteAction.AddToHomeScreen, 0, DevicePlatform.Desktop));
        Assert.Equal([SiteAction.HideToolbar, SiteAction.CopyLink],
            SiteControlTopActions.Default.Moving(SiteAction.HideToolbar, 0, DevicePlatform.Mobile).Actions.Take(2));
        Assert.Equal([SiteAction.ReloadPage],
            SiteControlTopActions.Restored(
                [SiteAction.CapturePage, SiteAction.ReloadPage, SiteAction.ReloadPage, SiteAction.ToggleConsole],
                DevicePlatform.Mobile).Actions);
        Assert.Same(SiteControlTopActions.Default,
            SiteControlTopActions.Restored([SiteAction.CapturePage], DevicePlatform.Mobile));
    }
}
