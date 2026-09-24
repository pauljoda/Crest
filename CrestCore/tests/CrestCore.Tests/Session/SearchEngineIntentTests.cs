using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A Space admits custom search engines under one set of rules, searches with
/// exactly one engine, and stores that choice in the spelling every build
/// reads; new browsing preferences sweep the Space under their retention.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void CustomSearchEnginesAreAdmittedSelectedAndStoredInTheNativeSpelling() {
        var session = SavedSession().Document["session"]!;
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var space = SpaceId(session["spaces"]![0]!);
        var (kagi, other) = (Guid.NewGuid(), Guid.NewGuid());
        JsonNode Stored() => JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!["browsingPreferences"]!;

        device.Send(new AddSearchEngine(device.Workspace, space, new(kagi, "  Kagi ", " https://kagi.com/search?q=%s ", ""), Selects: true));
        var preferences = Stored();
        Assert.Equal("custom:" + kagi.ToString("D"), preferences["selectedSearchProviderID"]!.GetValue<string>());
        // Builds that read only the legacy member fall back to Google.
        Assert.Equal("google", preferences["searchProvider"]!.GetValue<string>());
        Assert.Equal($"[{{\"id\":\"{kagi.ToString("D").ToUpperInvariant()}\",\"name\":\"Kagi\",\"searchURLTemplate\":\"https://kagi.com/search?q=%s\"}}]",
            preferences["customSearchProviders"]!.ToJsonString());
        var selected = core.Current.Spaces[0].Settings.BrowsingPreferences;
        Assert.Equal(((BuiltInSearchEngine?)null, (Guid?)kagi), (selected.SelectedBuiltInEngine, selected.SelectedCustomEngineId));

        device.Send(new AddSearchEngine(device.Workspace, space, new(other, "Example", "https://example.com/?q={searchTerms}", null), Selects: false));
        device.Send(new UpdateSearchEngine(device.Workspace, space,
            new(kagi, "Kagi Search", "https://kagi.com/search?q=%s", "https://kagi.com/api/autosuggest?q=%s")));
        var engines = Stored()["customSearchProviders"]!.AsArray();
        Assert.Equal(["Kagi Search", "Example"], engines.Select(e => e!["name"]!.GetValue<string>()));
        Assert.Equal("https://kagi.com/api/autosuggest?q=%s", engines[0]!["suggestionURLTemplate"]!.GetValue<string>());

        device.Send(new SelectSearchEngine(device.Workspace, space, BuiltInSearchEngine.Brave, null));
        Assert.Equal(("brave", "brave"), (Stored()["selectedSearchProviderID"]!.GetValue<string>(), Stored()["searchProvider"]!.GetValue<string>()));
        device.Send(new SelectSearchEngine(device.Workspace, space, null, kagi));

        // Removing the selected engine searches with Google.
        device.Send(new RemoveSearchEngine(device.Workspace, space, kagi));
        Assert.Equal("google", Stored()["selectedSearchProviderID"]!.GetValue<string>());
        Assert.Single(Stored()["customSearchProviders"]!.AsArray());
        Assert.Equal(new UnknownSearchEngine(kagi), Assert.Throws<Rejected>(() =>
            device.Send(new SelectSearchEngine(device.Workspace, space, null, kagi))).Rejection);
        Assert.Equal(new UnknownSearchEngine(other), Assert.Throws<Rejected>(() =>
            device.Send(new SelectSearchEngine(device.Workspace, space, BuiltInSearchEngine.Bing, other))).Rejection);
    }

    [Fact]
    public void RefusedCustomSearchEnginesLeaveTheSpaceUnchanged() {
        var session = SavedSession().Document["session"]!;
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var space = SpaceId(session["spaces"]![0]!);
        device.Send(new AddSearchEngine(device.Workspace, space, new(Guid.NewGuid(), "Café", "https://example.org/?q=%s", null), Selects: false));
        var admitted = core.Current;

        var duplicate = new AddSearchEngine(device.Workspace, space, new(Guid.NewGuid(), "CAFE", "https://example.com/?q=%s", null), Selects: false);
        Assert.IsType<DuplicateSearchEngineName>(device.Query(new CanSend(duplicate)).Refusal);
        Assert.Equal(new DuplicateSearchEngineName(), Assert.Throws<Rejected>(() => device.Send(duplicate)).Rejection);
        Assert.Equal(new InvalidSearchEngine(SearchEngineFlaw.UnsafeHost), Assert.Throws<Rejected>(() => device.Send(new AddSearchEngine(
            device.Workspace, space, new(Guid.NewGuid(), "Local", "https://localhost/?q=%s", null), Selects: false))).Rejection);
        var stranger = Guid.NewGuid();
        Assert.Equal(new UnknownSearchEngine(stranger), Assert.Throws<Rejected>(() => device.Send(new UpdateSearchEngine(
            device.Workspace, space, new(stranger, "Nothing", "https://example.net/?q=%s", null)))).Rejection);
        Assert.Same(admitted, core.Current);

        for (int index = 1; index < SearchPreferences.MaximumCustomProviders; index++)
            device.Send(new AddSearchEngine(device.Workspace, space,
                new(Guid.NewGuid(), $"Engine {index}", $"https://e{index}.example/?q=%s", null), Selects: false));
        Assert.Equal(new SearchEngineLimitReached(SearchPreferences.MaximumCustomProviders), Assert.Throws<Rejected>(() => device.Send(
            new AddSearchEngine(device.Workspace, space, new(Guid.NewGuid(), "One more", "https://more.example/?q=%s", null), Selects: false)))
            .Rejection);
    }

    [Fact]
    public void NewBrowsingPreferencesSweepTheSpaceUnderTheirRetention() {
        var session = SavedSession().Document["session"]!;
        session["spaces"]![0]!["history"] = new JsonArray(new JsonObject {
            ["id"] = Guid.NewGuid().ToString(),
            ["url"] = "https://example.com/old",
            ["title"] = "Old visit",
            ["firstVisitedAt"] = 0.0,
            ["lastVisitedAt"] = 0.0,
            ["visitCount"] = 1
        });
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var space = core.Current.Spaces[0];
        var preferences = space.Settings.BrowsingPreferences;
        Assert.Single(space.History);

        device.Send(new SetBrowsingPreferences(device.Workspace, space.Id, SearchSuggestionsEnabled: true, preferences.CurrentTabCleanup,
            preferences.ContentBlocking, preferences.DataRetention));
        Assert.Single(core.Current.Spaces[0].History);

        device.Send(new SetBrowsingPreferences(device.Workspace, space.Id, SearchSuggestionsEnabled: true, preferences.CurrentTabCleanup,
            preferences.ContentBlocking, preferences.DataRetention with { History = DataRetention.OneDay }));
        var swept = core.Current.Spaces[0];
        Assert.Empty(swept.History);
        Assert.Equal((true, DataRetention.OneDay),
            (swept.Settings.BrowsingPreferences.SearchSuggestionsEnabled, swept.Settings.BrowsingPreferences.DataRetention.History));
    }
}
