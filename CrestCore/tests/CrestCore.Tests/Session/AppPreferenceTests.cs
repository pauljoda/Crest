using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The persistent workspace imports the old settings once and keeps the
/// preferences on this device; the launch plan reads its startup choice.
public sealed partial class BrowserContractsTests {
    private static LaunchPlan LaunchPlan(Guid workspace, DevicePlatform? platform = null, LaunchEnvironment? environment = null) =>
        new(workspace, platform ?? DevicePlatform.Desktop, environment ?? LaunchEnvironment.Installed);

    private static LegacyAppPreferences LegacyPreferences() => new(StartupBehavior: "lastActiveTab", OffersTranslation: false,
        AutomaticallyTranslates: true, TranslationRules: """{"sources":{"es":{"isEnabled":true,"targetID":"en"}}}""",
        ChecksSpelling: true, AutomaticallyEntersPictureInPicture: false, SavedTabClosePolicy: "returnToSavedURL",
        SavedTabFaviconReturnsToSavedUrl: true, SplitFocusFollowsMouse: true);

    [Fact]
    public void LegacyPreferencesImportOnceAndPersistWithTheSession() {
        var session = SavedSession().Document["session"]!;
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var authority = device.Authority;
            device.Send(new AdoptSetupCompletion(Completed: true));
            Assert.Equal(StartupBehavior.ShowStartPage, device.Query(LaunchPlan(device.Workspace)).Startup);
            device.Send(new ImportAppPreferences(device.Workspace, LegacyPreferences()));
            saved = authority.Checkpoint().Read("core");
        }
        var stored = JsonNode.Parse(saved)!["appPreferences"]!;
        Assert.Equal("lastActiveTab", stored["startupBehavior"]!.GetValue<string>());
        Assert.False(stored["offersTranslation"]!.GetValue<bool>());
        Assert.True(stored["automaticallyTranslates"]!.GetValue<bool>());
        Assert.Equal("en", stored["translationRules"]!["sources"]!["es"]!["targetID"]!.GetValue<string>());
        Assert.True(stored["checksSpelling"]!.GetValue<bool>());
        Assert.False(stored["automaticallyEntersPictureInPicture"]!.GetValue<bool>());
        Assert.Equal(("returnToSavedURL", "returnToSavedURL"),
            (stored["pinnedTabsAfterClosing"]!.GetValue<string>(), stored["savedTabsAfterClosing"]!.GetValue<string>()));
        Assert.True(stored["savedTabFaviconReturnsToSavedURL"]!.GetValue<bool>());
        Assert.True(stored["splitFocusFollowsMouse"]!.GetValue<bool>());

        // A later launch finds the record and never imports over it again.
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority;
        var kept = restored.Current.AppPreferences;
        relaunched.Send(new ImportAppPreferences(relaunched.Workspace, new("showStartPage", null, null, null, false, null, null, null,
            null)));
        Assert.Same(kept, restored.Current.AppPreferences);
        relaunched.Send(new AdoptSetupCompletion(Completed: true));
        Assert.Equal(StartupBehavior.LastActiveTab, relaunched.Query(LaunchPlan(relaunched.Workspace)).Startup);
    }

    [Fact]
    public void AStoredCloseChoiceFromBeforePinnedAndSavedTabsChoseApartSeedsBoth() {
        var session = SavedSession().Document["session"]!;
        session["appPreferences"] = new JsonObject { ["savedTabClosePolicy"] = "returnToSavedURL" };
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var preferences = device.Authority.Current.AppPreferences!;
            Assert.Equal((SavedTabClosePolicy.ReturnToSavedUrl, SavedTabClosePolicy.ReturnToSavedUrl),
                (preferences.PinnedTabClose, preferences.SavedTabClose));
            device.Send(new SetAppPreferences(device.Workspace,
                preferences with { PinnedTabClose = SavedTabClosePolicy.ResumeLastLocation }));
            saved = device.Authority.Checkpoint().Read("core");
        }

        // The record is written back with a choice for each and without the
        // shared one, so changing one choice never brings the other back.
        var stored = JsonNode.Parse(saved)!["appPreferences"]!.AsObject();
        Assert.Equal(("resumeLastLocation", "returnToSavedURL", false), (stored["pinnedTabsAfterClosing"]!.GetValue<string>(),
            stored["savedTabsAfterClosing"]!.GetValue<string>(), stored.ContainsKey("savedTabClosePolicy")));
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority.Current.AppPreferences!;
        Assert.Equal((SavedTabClosePolicy.ResumeLastLocation, SavedTabClosePolicy.ReturnToSavedUrl),
            (restored.PinnedTabClose, restored.SavedTabClose));
    }

    [Fact]
    public void PictureInPictureSwitchPreferencesPersistIndependentlyOfTheTabSwitch() {
        var session = SavedSession().Document["session"]!;
        session["appPreferences"] = new JsonObject { ["automaticallyEntersPictureInPicture"] = false };
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var preferences = device.Authority.Current.AppPreferences!;
            Assert.False(preferences.AutomaticallyEntersPictureInPicture);
            Assert.False(preferences.FloatsVideoOnAppSwitch);
            Assert.False(preferences.FloatsVideoOnDesktopSwitch);
            Assert.True(preferences.RedocksVideoOnFocus);

            var appSwitch = preferences with { FloatsVideoOnAppSwitch = true };
            device.Send(new SetAppPreferences(device.Workspace, appSwitch));
            Assert.Equal(appSwitch, device.Authority.Current.AppPreferences);

            var desktopSwitch = appSwitch with { FloatsVideoOnDesktopSwitch = true, RedocksVideoOnFocus = false };
            device.Send(new SetAppPreferences(device.Workspace, desktopSwitch));
            Assert.Equal(desktopSwitch, device.Authority.Current.AppPreferences);
            saved = device.Authority.Checkpoint().Read("core");
        }

        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority.Current.AppPreferences!;
        Assert.False(restored.AutomaticallyEntersPictureInPicture);
        Assert.True(restored.FloatsVideoOnAppSwitch);
        Assert.True(restored.FloatsVideoOnDesktopSwitch);
        Assert.False(restored.RedocksVideoOnFocus);
    }

    [Fact]
    public void CloudReplacementNeverCarriesOrReplacesAppPreferences() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session["appPreferences"] = new JsonObject { ["startupBehavior"] = "lastActiveTab", ["futureChoice"] = 3 };
        var journal = new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()))));
        var transition = Transition(journal, session.DeepClone(), new JsonArray(), replacing: true, now: 800000000.0);
        Assert.True(JsonNode.DeepEquals(session["appPreferences"], transition.Materialization["session"]!["appPreferences"]));
    }
}
