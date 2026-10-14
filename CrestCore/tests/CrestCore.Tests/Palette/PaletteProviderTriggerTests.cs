using System.Text.Json.Nodes;

using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Actions - Provider Triggers

    [Fact]
    public void SpaceCanEnterAProviderIndependentlyOfTab() {
        var (session, space) = PaletteSession([]);
        session["appPreferences"] = new JsonObject {
            ["palette"] = new JsonObject {
                ["searchesSitesWithTab"] = false,
                ["providerSpaceTrigger"] = "prefixedShortcut"
            }
        };
        using var device = new TestDevice(session);
        var window = device.Open(space);

        var answer = device.Query(Asking(window, "$yt cats"));

        Assert.Equal("youTube", answer.Entry?.Provider?.Name);
        Assert.Equal("cats", answer.Entry?.Text);
        Assert.Equal("https://www.youtube.com/results?search_query=cats", answer.Groups[0].Rows[0].Address);
    }

    [Theory]
    [InlineData("off", "$yt cats", null)]
    [InlineData("off", "yt cats", null)]
    [InlineData("prefixedShortcut", "$yt cats", "youTube")]
    [InlineData("prefixedShortcut", "yt cats", null)]
    [InlineData("shortcut", "yt cats", "youTube")]
    [InlineData("shortcut", "$yt cats", "youTube")]
    [InlineData("shortcut", "YT cats", "youTube")]
    [InlineData("shortcut", "www.youtube.com cats", null)]
    [InlineData("shortcut", "unknown cats", null)]
    [InlineData("shortcut", "yt", null)]
    public void SpaceTriggerModesEnterOnlyAnEnabledExactShortcut(string mode, string text, string? provider) {
        var (session, space) = PaletteSession([]);
        session["appPreferences"] = new JsonObject {
            ["palette"] = new JsonObject { ["searchesSitesWithTab"] = false, ["providerSpaceTrigger"] = mode }
        };
        using var device = new TestDevice(session);
        var window = device.Open(space);
        Assert.Equal(provider, device.Query(Asking(window, text)).Entry?.Provider?.Name);
        device.Send(new SetSearchProviderEnabled(BuiltInSearchProvider.YouTube, IsEnabled: false));
        Assert.Null(device.Query(Asking(window, text)).Entry);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void ExistingPalettePreferencesKeepTheirPreviousSpaceTrigger(bool tabEnabled) {
        var (session, space) = PaletteSession([]);
        session["appPreferences"] = new JsonObject {
            ["palette"] = new JsonObject { ["searchesSitesWithTab"] = tabEnabled }
        };
        using var device = new TestDevice(session);
        var answer = device.Query(Asking(device.Open(space), "$yt cats"));
        Assert.Equal(tabEnabled, answer.Entry?.Provider?.Name == "youTube");
    }

    [Fact]
    public void IndependentTriggerChoicesPersistAcrossRelaunch() {
        var (session, space) = PaletteSession([]);
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var preferences = AppPreferences.Default with {
                Palette = PalettePreferences.Default with {
                    SearchesSitesWithTab = true,
                    ProviderSpaceTrigger = SearchProviderSpaceTrigger.Off
                }
            };
            device.Send(new SetAppPreferences(device.Workspace, preferences));
            saved = device.Authority.Checkpoint().Read("core");
        }
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority.Current.AppPreferences!.Palette;
        Assert.True(restored.SearchesSitesWithTab);
        Assert.Equal(SearchProviderSpaceTrigger.Off, restored.ProviderSpaceTrigger);
        var window = relaunched.Open(space);
        Assert.Null(relaunched.Query(Asking(window, "$yt cats")).Entry);
        Assert.NotNull(relaunched.Query(Asking(window, "yt")).OfferedSearch);
    }

    #endregion
}
