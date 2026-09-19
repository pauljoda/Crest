using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    [Fact]
    public void AddressInputUsesItsSpacesProviderAndEscapesTheWholeQuery()
    {
        var (core, window, space) = Kernel();
        core.Workspace.Space(space).SetSearch(SearchPreferences.Default.Select("duckDuckGo", false));
        var opened = core.Process(Message("core.navigate_input", new()
        { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString(), ["input"] = "  two words & π  " }));
        Assert.Equal("https://duckduckgo.com/?q=two%20words%20%26%20%CF%80", opened.Single(e => e.Type == "engine.create_page").Payload["url"]!.GetValue<string>());
        var preferences = SearchPreferences.Default;
        Assert.Equal("http://localhost:8080/path", preferences.Resolve("localhost:8080/path", false));
        Assert.Equal("https://example.com/path", preferences.Resolve("example.com/path", false));
        Assert.Equal("https://example.org/", preferences.Resolve("https://example.org", false));
        Assert.Equal("chrome://extensions", preferences.Resolve("chrome://extensions", true));
        Assert.Throws<BrowserRuleException>(() => preferences.Resolve("https://user:password@example.org", false));
    }
    [Fact]
    public void CustomSearchTemplatesRejectCredentialAndLocalTargetsAndHaveStableSelectionFallback()
    {
        foreach (var template in new[] {
            "http://example.org/?q=%s", "https://example.org/?q=%s&token=secret", "https://localhost/?q=%s",
            "https://192.168.1.1/?q=%s", "https://%s.example.org/", "https://example.org/#%s",
            "https://example.org/?q=%s&other={searchTerms}", "https://example.org/?q=%s&bad=%z",
            "https://user:secret@example.org/?q=%s", "https://example.org:8443/?q=%s" })
            Assert.Throws<BrowserRuleException>(() => SearchProvider.Custom(Guid.NewGuid(), "Custom", template, null));
        var id = Guid.NewGuid(); var provider = SearchProvider.Custom(id, "Café", "https://example.org/find/{searchTerms}", null);
        var preferences = SearchPreferences.Default.Upsert(provider).Select(provider.Id, true);
        Assert.Equal("https://example.org/find/a%2Fb%3Fc", preferences.Resolve("a/b?c", false));
        Assert.Throws<BrowserRuleException>(() => preferences.Upsert(SearchProvider.Custom(Guid.NewGuid(), "CAFE", "https://example.com/?q=%s", null)));
        Assert.Equal("google", preferences.Remove(id).SelectedId);
        Assert.Equal(provider.Id, preferences.SelectedId);
    }
    [Fact]
    public void SearchChangesRoundTripThroughLegacyStorageWithoutReplacingAdjacentPreferences()
    {
        var fixture = SavedSession(); var document = new LegacySessionDocument(fixture.Document);
        var workspace = BrowserWorkspace.Restore(document.Read(new SystemIdSource()), new SystemIdSource(), new SystemClock());
        var space = workspace.Spaces[0];
        var provider = SearchProvider.Custom(Guid.NewGuid(), "Reference", "https://example.org/?q=%s", "https://example.org/suggest?q=%s");
        space.SetSearch(space.Search.Upsert(provider).Select(provider.Id, true));
        var saved = document.Write(workspace.Capture());
        var preferences = saved["session"]!["spaces"]![0]!["browsingPreferences"]!;
        Assert.True(preferences["futureFlag"]!.GetValue<bool>());
        Assert.Equal("google", preferences["searchProvider"]!.GetValue<string>());
        var restored = new LegacySessionDocument(saved).Read(new SystemIdSource()).Spaces[0].Search!;
        Assert.Equal(provider.Id, restored.SelectedId); Assert.True(restored.SuggestionsEnabled);
        Assert.Equal(provider, Assert.Single(restored.CustomProviders));
    }
}
