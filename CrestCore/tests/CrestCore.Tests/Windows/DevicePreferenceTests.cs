using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// How pages start, where each Space's downloads go and whether the device
/// syncs with iCloud are device state: the device store keeps them, each
/// carried once from what an installed release kept in its defaults and never
/// read from there again.
public sealed partial class BrowserContractsTests {
    private static PagePreferences Pages(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<PagePreferencesChanged>()).Preferences;

    private static IReadOnlyList<SpaceDownloadPreferences> Downloads(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<DownloadPreferencesChanged>()).Spaces;

    private static bool Syncs(IReadOnlyList<Change> changes) => Assert.Single(changes.OfType<CloudSyncAdvanced>()).Status.IsEnabled;

    [Fact]
    public void EachDevicePreferenceAReleaseKeptIsAdoptedOnceAndEveryChangeSurvivesARelaunch() {
        using var directory = new StorageDirectory();
        Guid asking = Guid.NewGuid(), filing = Guid.NewGuid();
        var folder = new DownloadFolder("Invoices", [1, 2, 3]);
        // The defaults as the release kept them: a zoom past the range, and a
        // Space that kept nothing a Space would not do anyway.
        var legacy = new AdoptDevicePreferences(DefaultPageZoom: 9, BackgroundPageActivity: "throttle", AllowsHighFrameRate: true,
            SyncsWithICloud: false, [
                new SpaceDownloadPreferences(asking, AsksWhereToSave: true, Folder: null),
                new SpaceDownloadPreferences(filing, AsksWhereToSave: false, folder),
                new SpaceDownloadPreferences(Guid.NewGuid(), AsksWhereToSave: false, Folder: null)
            ]);
        var adopted = new PagePreferences(PagePreferences.MaximumZoom, BackgroundPageActivity.Throttle, AllowsHighFrameRate: true);
        SpaceDownloadPreferences[] adoptedDownloads = [new(asking, true, null), new(filing, false, folder)];
        PagePreferences edited;
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            var changes = app.Send(legacy);
            Assert.Equal(adopted, Pages(changes));
            Assert.Equal(adoptedDownloads, Downloads(changes));
            Assert.False(Syncs(app.Send(new ConfigureCloudSync(CanReachCloud: false))));
            // A later adoption carries nothing more, whatever the defaults hold
            // now, and publishes what the store holds.
            var again = app.Send(new AdoptDevicePreferences(1.5, "suspend", false, SyncsWithICloud: true,
                [new SpaceDownloadPreferences(asking, AsksWhereToSave: false, Folder: null)]));
            Assert.Equal(adopted, Pages(again));
            Assert.Equal(adoptedDownloads, Downloads(again));

            app.Send(new SetDefaultPageZoom(double.NaN));
            edited = Pages(app.Send(new SetBackgroundPageActivity(BackgroundPageActivity.Suspend)));
            Assert.Equal(new PagePreferences(PagePreferences.StandardZoom, BackgroundPageActivity.Suspend, AllowsHighFrameRate: true), edited);
            Assert.Empty(app.Send(new SetHighFrameRate(true)).OfType<PagePreferencesChanged>());
            // A Space set back to the Downloads folder keeps nothing.
            Assert.Equal([adoptedDownloads[1]],
                Downloads(app.Send(new SetSpaceDownloads(new SpaceDownloadPreferences(asking, AsksWhereToSave: false, Folder: null)))));
            Assert.True(Syncs(app.Send(new SetCloudSyncEnabled(true))));
        }

        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        var reopened = relaunched.Send(legacy);
        Assert.Equal(edited, Pages(reopened));
        Assert.Equal([adoptedDownloads[1]], Downloads(reopened));
        Assert.True(Syncs(relaunched.Send(new ConfigureCloudSync(CanReachCloud: false))));
    }
}
