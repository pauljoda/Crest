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
        Assert.Equal("returnToSavedURL", stored["savedTabClosePolicy"]!.GetValue<string>());
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

    /// The link menu's arrangement persists on this device, naming every row
    /// once: a repeated row keeps its first place, a row it never named, such
    /// as one a later release adds, joins at the end and shows, and a row this
    /// build cannot name is left out.
    [Fact]
    public void LinkMenuArrangementPersistsWithEveryRowOnce() {
        byte[] saved;
        using (var device = new TestDevice(SavedSession().Document["session"]!)) {
            device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with {
                LinkMenu = new([new(LinkMenuRow.Peek, IsShown: true), new(LinkMenuRow.SplitView, IsShown: false),
                    new(LinkMenuRow.Peek, IsShown: false)])
            }));
            saved = device.Authority.Checkpoint().Read("core");
        }
        using (var relaunched = new TestDevice(JsonNode.Parse(saved)!)) {
            LinkMenuChoice[] expected = [new(LinkMenuRow.Peek, true), new(LinkMenuRow.SplitView, false),
                new(LinkMenuRow.NewTab, true), new(LinkMenuRow.OtherSpaces, true), new(LinkMenuRow.Search, true)];
            Assert.Equal(expected, relaunched.Authority.Current.AppPreferences!.LinkMenu.Rows);
        }

        var stored = JsonNode.Parse(saved)!;
        stored["appPreferences"]!["linkMenu"] = new JsonObject {
            ["rows"] = new JsonArray(new JsonObject { ["row"] = "future", ["isShown"] = false },
                new JsonObject { ["row"] = "search", ["isShown"] = false })
        };
        using var later = new TestDevice(stored);
        var rows = later.Authority.Current.AppPreferences!.LinkMenu.Rows;
        Assert.Equal(new LinkMenuChoice(LinkMenuRow.Search, false), rows[0]);
        Assert.Equal(LinkMenuRow.All.Count, rows.Count);
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
