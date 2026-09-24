using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static JsonObject Engine(Guid id, string name, string template, string? suggestions = null) => new() {
        ["id"] = id.ToString("D"),
        ["name"] = name,
        ["searchURLTemplate"] = template,
        ["suggestionURLTemplate"] = suggestions
    };

    [Fact]
    public void CustomSearchEngineCommandsKeepTheNativePreferenceFormat() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var kagi = Guid.NewGuid();
        var added = authority.PrepareCommand(1, SpaceCommand(session, "space.search_provider.upsert", new() {
            ["provider"] = Engine(kagi, "  Kagi ", " https://kagi.com/search?q=%s ", ""),
            ["selects"] = true
        }));
        added.Commit();
        session = JsonNode.Parse(added.Output)!["session"]!;
        var preferences = session["spaces"]![0]!["browsingPreferences"]!;
        Assert.Equal("custom:" + kagi.ToString("D"), preferences["selectedSearchProviderID"]!.GetValue<string>());
        Assert.Equal("google", preferences["searchProvider"]!.GetValue<string>());
        Assert.Equal("after12Hours", preferences["currentTabCleanupPolicy"]?.GetValue<string>() ?? "after12Hours");
        Assert.Equal($"[{{\"id\":\"{kagi.ToString("D").ToUpperInvariant()}\",\"name\":\"Kagi\",\"searchURLTemplate\":\"https://kagi.com/search?q=%s\"}}]",
            preferences["customSearchProviders"]!.ToJsonString());

        var other = Guid.NewGuid();
        authority.PrepareCommand(2, SpaceCommand(session, "space.search_provider.upsert", new() {
            ["provider"] = Engine(other, "Example", "https://example.com/?q={searchTerms}"),
            ["selects"] = false
        })).Commit();
        var edited = authority.PrepareCommand(3, SpaceCommand(session, "space.search_provider.upsert", new() {
            ["provider"] = Engine(kagi, "Kagi Search", "https://kagi.com/search?q=%s", "https://kagi.com/api/autosuggest?q=%s")
        }));
        edited.Commit();
        session = JsonNode.Parse(edited.Output)!["session"]!;
        var engines = session["spaces"]![0]!["browsingPreferences"]!["customSearchProviders"]!.AsArray();
        Assert.Equal(["Kagi Search", "Example"], engines.Select(e => e!["name"]!.GetValue<string>()));
        Assert.Equal("https://kagi.com/api/autosuggest?q=%s", engines[0]!["suggestionURLTemplate"]!.GetValue<string>());

        var removed = authority.PrepareCommand(4, SpaceCommand(session, "space.search_provider.remove", new() { ["id"] = kagi.ToString("D") }));
        removed.Commit();
        preferences = JsonNode.Parse(removed.Output)!["session"]!["spaces"]![0]!["browsingPreferences"]!;
        Assert.Equal("google", preferences["selectedSearchProviderID"]!.GetValue<string>());
        Assert.Single(preferences["customSearchProviders"]!.AsArray());
    }

    [Fact]
    public void RejectedCustomSearchEnginesLeaveTheSpaceUnchanged() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        authority.PrepareCommand(1, SpaceCommand(session, "space.search_provider.upsert", new() {
            ["provider"] = Engine(Guid.NewGuid(), "Café", "https://example.org/?q=%s")
        })).Commit();
        var duplicate = Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(2, SpaceCommand(session,
            "space.search_provider.upsert", new() { ["provider"] = Engine(Guid.NewGuid(), "CAFE", "https://example.com/?q=%s") })));
        Assert.Equal(BrowserRuleCodes.DuplicateSearchName, duplicate.Code);
        var unsafeTemplate = Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(2, SpaceCommand(session,
            "space.search_provider.upsert", new() { ["provider"] = Engine(Guid.NewGuid(), "Local", "https://localhost/?q=%s") })));
        Assert.Equal(BrowserRuleCodes.UnsafeSearchTemplate, unsafeTemplate.Code);
        var saved = JsonNode.Parse(authority.Checkpoint(2).Read("core"))!;
        Assert.Single(saved["spaces"]![0]!["browsingPreferences"]!["customSearchProviders"]!.AsArray());
    }
}
