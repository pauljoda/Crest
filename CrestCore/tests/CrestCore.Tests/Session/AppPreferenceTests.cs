using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static readonly string[] LaunchFlags = [
        "testRuntime", "previewRuntime", "isolatedSession", "namedProfile", "isolatedCloudSync", "resetSession", "showcase",
        "inMemoryCredentials", "onboardingWelcome", "desktopSetup", "mobileSetup", "performanceHarness", "updateTestFeed"
    ];

    private static byte[] PreferenceCommand(string operation, JsonObject arguments) => Bytes(new JsonObject {
        ["version"] = 1,
        ["operation"] = operation,
        ["arguments"] = arguments
    });

    private static JsonObject SetPreference(string preference, JsonNode? value) => new() {
        ["preference"] = preference,
        ["value"] = value
    };

    private static byte[] LaunchRequest(string platform = "desktop", bool gate = false, params string[] enabled) {
        var environment = new JsonObject();
        foreach (var flag in LaunchFlags) environment[flag] = enabled.Contains(flag);
        return Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "launch.plan",
            ["platform"] = platform,
            ["environment"] = environment,
            ["hasActiveLaunchGate"] = gate
        });
    }

    /// Reads the plan and releases it uncommitted, as the native launch does.
    private static string Startup(NativeSessionAuthority authority, string platform = "desktop", bool gate = false,
        params string[] enabled) {
        var revision = authority.Revision;
        var plan = JsonNode.Parse(authority.PrepareCommand(LaunchRequest(platform, gate, enabled)).Output)!;
        Assert.Equal(revision, authority.Revision);
        return plan["startupBehavior"]!.GetValue<string>();
    }

    private static JsonObject LegacyPreferences() => new() {
        ["startupBehavior"] = "lastActiveTab",
        ["offersTranslation"] = false,
        ["automaticallyTranslates"] = true,
        ["translationRules"] = """{"sources":{"es":{"isEnabled":true,"targetID":"en"}}}""",
        ["checksSpelling"] = true,
        ["automaticallyEntersPictureInPicture"] = false,
        ["savedTabClosePolicy"] = "returnToSavedURL",
        ["savedTabFaviconReturnsToSavedURL"] = true,
        ["splitFocusFollowsMouse"] = true
    };

    [Fact]
    public void LegacyPreferencesImportOnceAndPersistWithTheSession() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        Assert.Equal("showStartPage", Startup(authority));

        authority.PrepareCommand(PreferenceCommand("preferences.import", new() { ["legacy"] = LegacyPreferences() })).Commit();
        var saved = JsonNode.Parse(authority.Checkpoint().Read("core"))!;
        var stored = saved["appPreferences"]!;
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
        var restored = new NativeSessionAuthority(Bytes(saved));
        var repeated = restored.PrepareCommand(PreferenceCommand("preferences.import", new() {
            ["legacy"] = new JsonObject { ["startupBehavior"] = "showStartPage", ["checksSpelling"] = false }
        }));
        Assert.Equal("lastActiveTab", JsonNode.Parse(repeated.Output)!["preferences"]!["startupBehavior"]!.GetValue<string>());
        repeated.Commit();
        Assert.Equal("lastActiveTab", Startup(restored));
        Assert.True(JsonNode.Parse(restored.Checkpoint().Read("core"))!["appPreferences"]!["checksSpelling"]!
            .GetValue<bool>());
    }

    [Fact]
    public void UnreadableLegacyValuesKeepTheirDefaults() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var imported = authority.PrepareCommand(PreferenceCommand("preferences.import", new() {
            ["legacy"] = new JsonObject {
                ["startupBehavior"] = "retiredChoice",
                ["translationRules"] = "not json",
                ["checksSpelling"] = "yes",
                ["savedTabClosePolicy"] = null
            }
        }));
        var stored = JsonNode.Parse(imported.Output)!["preferences"]!;
        Assert.Equal("showStartPage", stored["startupBehavior"]!.GetValue<string>());
        Assert.Empty(stored["translationRules"]!["sources"]!.AsObject());
        Assert.False(stored["checksSpelling"]!.GetValue<bool>());
        Assert.True(stored["offersTranslation"]!.GetValue<bool>());
        Assert.True(stored["automaticallyEntersPictureInPicture"]!.GetValue<bool>());
        Assert.Equal("resumeLastLocation", stored["savedTabClosePolicy"]!.GetValue<string>());
    }

    [Fact]
    public void OnlyPreferenceCommandsChangeTheRecord() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        authority.PrepareCommand(PreferenceCommand("preferences.set", SetPreference("checksSpelling", true))).Commit();
        authority.PrepareCommand(PreferenceCommand("preferences.set", SetPreference("startupBehavior", "lastActiveTab"))).Commit();
        var rule = authority.PrepareCommand(PreferenceCommand("preferences.translation_rule", new() {
            ["sourceID"] = "es-MX",
            ["targetID"] = "fr",
            ["isEnabled"] = true
        }));
        rule.Commit();
        Assert.Equal("fr", JsonNode.Parse(rule.Output)!["preferences"]!["translationRules"]!["sources"]!["es-MX"]!["targetID"]!
            .GetValue<string>());

        Assert.Equal(BrowserRuleCodes.UnknownPreference, Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(PreferenceCommand("preferences.set", SetPreference("sidebarDensity", 1)))).Code);
        Assert.Equal(BrowserRuleCodes.InvalidPreferenceValue, Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(PreferenceCommand("preferences.set", SetPreference("startupBehavior", "retiredChoice")))).Code);
        Assert.Equal(BrowserRuleCodes.InvalidPreferenceValue, Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(PreferenceCommand("preferences.set", SetPreference("checksSpelling", "true")))).Code);

        // A native value edit whose header omits the record keeps the owned one.
        var header = session.DeepClone().AsObject(); header.Remove("spaces");
        authority.Commit(Bytes(new JsonObject { ["version"] = 1, ["metadata"] = header, ["spaces"] = new JsonArray() }));
        var saved = JsonNode.Parse(authority.Checkpoint().Read("core"))!["appPreferences"]!;
        Assert.True(saved["checksSpelling"]!.GetValue<bool>());
        Assert.Equal("lastActiveTab", Startup(authority));
    }

    [Fact]
    public void CloudReplacementNeverCarriesOrReplacesAppPreferences() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session["appPreferences"] = new JsonObject { ["startupBehavior"] = "lastActiveTab", ["futureChoice"] = 3 };
        var journal = new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()))));
        var transition = NativeSyncSessionTransition.Prepare(journal, Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "replace",
            ["session"] = session.DeepClone(),
            ["preferences"] = SyncProjectionPreferences(),
            ["records"] = new JsonArray(),
            ["now"] = 800000000.0
        }));
        Assert.True(JsonNode.DeepEquals(session["appPreferences"], transition.Materialization["session"]!["appPreferences"]));
    }

    [Theory]
    [InlineData("desktop", false, "lastActiveTab")]
    [InlineData("desktop", true, "lastActiveTab")]
    [InlineData("mobile", false, "lastActiveTab")]
    public void TheLaunchPlanReadsTheSavedStartupChoice(string platform, bool gate, string expected) {
        var session = SavedSession().Document["session"]!.AsObject();
        session["appPreferences"] = new JsonObject { ["startupBehavior"] = "lastActiveTab" };
        Assert.Equal(expected, Startup(new NativeSessionAuthority(Bytes(session)), platform, gate));
        session["appPreferences"] = new JsonObject { ["startupBehavior"] = "showStartPage" };
        var showsStartPage = new NativeSessionAuthority(Bytes(session));
        Assert.Equal(gate ? "lastActiveTab" : "showStartPage", Startup(showsStartPage, platform, gate));
        // Setup and isolated fixtures restore their staged tab; the mobile showcase always opens the Start Page.
        Assert.Equal("lastActiveTab", Startup(showsStartPage, platform, false, "isolatedSession"));
        Assert.Equal("showStartPage", Startup(new NativeSessionAuthority(Bytes(session.DeepClone())), "mobile", false, "showcase"));
    }

    [Fact]
    public void OnlyThePersistentWorkspaceOwnsAppPreferences() {
        var session = SavedSession().Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session));
        var borrowed = Borrow(owner, session);
        Assert.Equal(BrowserRuleCodes.BorrowedProfileRequiresOwner, Assert.Throws<BrowserRuleException>(() =>
            borrowed.PrepareCommand(PreferenceCommand("preferences.set", SetPreference("checksSpelling", true)))).Code);
        var privateSession = session.DeepClone(); privateSession["coreWorkspaceKind"] = "private";
        var privateAuthority = new NativeSessionAuthority(Bytes(privateSession));
        Assert.Equal(BrowserRuleCodes.PersistentWorkspaceRequired, Assert.Throws<BrowserRuleException>(() =>
            privateAuthority.PrepareCommand(PreferenceCommand("preferences.set", SetPreference("checksSpelling", true)))).Code);
    }
}
