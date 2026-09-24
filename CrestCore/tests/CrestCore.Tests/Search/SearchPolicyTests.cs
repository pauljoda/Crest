using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class SearchPolicyTests {
    private const string KagiId = "00000000-0000-0000-0000-000000000264";

    private static JsonNode Evaluate(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    private static JsonObject Custom(string search, string? suggestions = null, string name = "Kagi", string id = KagiId) => new() {
        ["id"] = "custom:" + id,
        ["name"] = name,
        ["searchURLTemplate"] = search,
        ["suggestionURLTemplate"] = suggestions
    };

    private static string? Url(JsonObject provider, string query, string purpose = "search") =>
        Evaluate(new() { ["operation"] = "search.url", ["searchProvider"] = provider, ["query"] = query, ["purpose"] = purpose })["url"]
            ?.GetValue<string>();

    private static CustomSearchEngine Engine(string name, string template, Guid? id = null) =>
        new(id ?? Guid.Parse(KagiId), name, template, "  ");

    /// The rule admitting `engine` next to `existing` breaks, or null when it is admitted.
    private static Rejection? Refusal(CustomSearchEngine engine, params CustomSearchEngine[] existing) {
        try {
            new Search().Answer(new CustomSearchEngineAdmission(engine, existing));
            return null;
        } catch (Rejected rejected) {
            return rejected.Rejection;
        }
    }

    [Theory]
    [InlineData("native mac browser", "native%20mac%20browser")]
    [InlineData("a+b", "a%2Bb")]
    [InlineData("fish & chips=good", "fish%20%26%20chips%3Dgood")]
    [InlineData("C# #tag", "C%23%20%23tag")]
    [InlineData("Café 日本", "Caf%C3%A9%20%E6%97%A5%E6%9C%AC")]
    [InlineData("🦊", "%F0%9F%A6%8A")]
    [InlineData("a/b?c", "a%2Fb%3Fc")]
    [InlineData("-._~", "-._~")]
    [InlineData("%s {searchTerms}", "%25s%20%7BsearchTerms%7D")]
    [InlineData("100%", "100%25")]
    [InlineData("", "")]
    public void QueriesArePercentEncodedOnceAsUtf8IntoTheSinglePlaceholder(string query, string encoded) {
        Assert.Equal("https://www.google.com/search?q=" + encoded, Url(new() { ["id"] = "google" }, query));
        Assert.Equal("https://kagi.com/find/" + encoded + "?source=crest",
            Url(Custom("https://kagi.com/find/{searchTerms}?source=crest"), query));
    }

    [Fact]
    public void TheBuiltInCatalogOwnsEveryEnginesResultsAndSuggestionTemplates() {
        var expected = new Dictionary<string, (string Search, string Suggestions)> {
            ["google"] = ("https://www.google.com/search?q=a%20b", "https://www.google.com/complete/search?client=chrome&q=a%20b"),
            ["duckDuckGo"] = ("https://duckduckgo.com/?q=a%20b", "https://duckduckgo.com/ac/?q=a%20b&type=list"),
            ["bing"] = ("https://www.bing.com/search?q=a%20b", "https://www.bing.com/osjson.aspx?query=a%20b"),
            ["ecosia"] = ("https://www.ecosia.org/search?q=a%20b", "https://ac.ecosia.org/autocomplete?q=a%20b&type=list"),
            ["brave"] = ("https://search.brave.com/search?q=a%20b", "https://search.brave.com/api/suggest?q=a%20b")
        };
        Assert.Equal(expected.Keys, SearchProvider.All.Select(p => p.Name));
        foreach (var (id, urls) in expected) {
            Assert.Equal(urls.Search, Url(new() { ["id"] = id }, "a b"));
            Assert.Equal(urls.Suggestions, Url(new() { ["id"] = id }, "a b", "suggestions"));
        }
        Assert.Throws<BrowserRuleException>(() => Url(new() { ["id"] = "yahoo" }, "a"));
        // A built-in identity cannot smuggle its own template.
        Assert.Throws<ProtocolException>(() => Url(new() { ["id"] = "google", ["searchURLTemplate"] = "https://evil.example/?q=%s" }, "a"));
    }

    [Fact]
    public void CustomEnginesBuildTheirOwnURLsAndAStoredInvalidOneNeverRuns() {
        Assert.Equal("https://kagi.com/api/autosuggest?q=crest%20browser",
            Url(Custom("https://kagi.com/search?q=%s", "https://kagi.com/api/autosuggest?q=%s"), "crest browser", "suggestions"));
        Assert.Null(Url(Custom("https://kagi.com/search?q=%s"), "crest", "suggestions"));
        Assert.Equal("https://www.google.com/search?q=secret", Url(Custom("http://127.0.0.1/search?q=%s"), "secret"));
        Assert.Throws<ProtocolException>(() => Url(Custom("https://kagi.com/search?q=%s", id: "ABCDEF00-0000-0000-0000-000000000264"), "a"));
        Assert.Throws<ProtocolException>(() => Url(new() { ["id"] = "google" }, "a", "images"));
    }

    [Fact]
    public void AddressIntentSearchesWithTheSpacesProvider() {
        var intent = Evaluate(new() {
            ["operation"] = "address.intent",
            ["input"] = "webkit process model",
            ["searchProvider"] = new JsonObject { ["id"] = "duckDuckGo" }
        });
        Assert.Equal("https://duckduckgo.com/?q=webkit%20process%20model", intent["url"]!.GetValue<string>());
        Assert.Equal("webkit process model", intent["searchQuery"]!.GetValue<string>());
    }

    [Theory]
    [InlineData("https://example.com/search?q=%s", "Example", null)]
    [InlineData("  https://example.com/search?q=%s  ", "  Example  ", null)]
    [InlineData("https://example.com:443/search/%s", "Example", null)]
    [InlineData("https://example.com/search?q=%s", "   ", "emptyName")]
    [InlineData("https://example.com/search?q=%s", "12345678901234567890123456789012345678901234567890123456789012345", "nameTooLong")]
    [InlineData("https://example.com/search", "Example", "missingPlaceholder")]
    [InlineData("https://example.com/?q=%s&again=%s", "Example", "ambiguousPlaceholder")]
    [InlineData("https://example.com/?q=%s&again={searchTerms}", "Example", "ambiguousPlaceholder")]
    [InlineData("https://example.com/?q=%s&bad=%zz", "Example", "invalidTemplate")]
    [InlineData("http://example.com/?q=%s", "Example", "requiresHttps")]
    [InlineData("example.com/?q=%s", "Example", "requiresHttps")]
    [InlineData("https://user:password@example.com/?q=%s", "Example", "credentialsInTemplate")]
    [InlineData("https://example.com:8443/?q=%s", "Example", "nonstandardPort")]
    [InlineData("https://%s.example.com/search", "Example", "unsafeHost")]
    [InlineData("https://localhost/search?q=%s", "Example", "unsafeHost")]
    [InlineData("https://printer.local/search?q=%s", "Example", "unsafeHost")]
    [InlineData("https://192.168.1.1/search?q=%s", "Example", "unsafeHost")]
    [InlineData("https://example.com/search#q=%s", "Example", "placeholderInFragment")]
    [InlineData("https://example.com/search?Token=secret&q=%s", "Example", "secretInTemplate")]
    [InlineData("https://example.com/search?api%5Fkey=secret&q=%s", "Example", "secretInTemplate")]
    public void CustomEngineValidationNamesTheRuleThePersonBroke(string template, string name, string? flaw) {
        var engine = Engine(name, template);
        Assert.Equal(SearchEngineFlaw.Named(flaw) is { } expected ? new InvalidSearchEngine(expected) : null, Refusal(engine));
        if (flaw is null) {
            var admitted = new Search().Answer(new CustomSearchEngineAdmission(engine, []));
            Assert.Equal(new CustomSearchEngine(engine.Id, "Example", template.Trim(), null), admitted);
        }
    }

    [Fact]
    public void AdmissionRejectsFoldedDuplicateNamesAndTheThirtyThirdEngine() {
        var engine = Engine("Café", "https://example.org/?q=%s");
        Assert.Equal(new DuplicateSearchEngineName(), Refusal(engine, Engine("  CAFE ", "https://a.example/?q=%s", Guid.NewGuid())));
        Assert.Equal(new InvalidSearchEngine(SearchEngineFlaw.TemplateTooLong),
            Refusal(Engine("Long", "https://example.com/?q=%s&p=" + new string('a', 2048))));
        // Editing an engine may keep its own name.
        Assert.Null(Refusal(engine, engine));
        var full = Enumerable.Range(0, 32).Select(i => Engine($"Engine {i}", "https://a.example/?q=%s", Guid.NewGuid())).ToArray();
        Assert.Equal(new SearchEngineLimitReached(SearchPreferences.MaximumCustomProviders), Refusal(engine, full));
        full[5] = engine with { Name = "Engine 5" };
        Assert.Null(Refusal(engine, full));
        // Session commands still report the same rules as their codes.
        Assert.Equal(BrowserRuleCodes.SearchProviderLimit, BrowserRuleCodes.SearchEngine(new SearchEngineLimitReached(32)));
        Assert.Equal(BrowserRuleCodes.SearchTemplatePort,
            Assert.Throws<BrowserRuleException>(() => SearchPreferences.Custom(Guid.NewGuid(), "Port", "https://a.example:8443/?q=%s", null)).Code);
    }

    [Fact]
    public void StoredEnginesRestoreWithoutInvalidOrDuplicateEntriesAndKeepASafeSelection() {
        JsonObject Stored(string id, string template) =>
            new() { ["id"] = id, ["name"] = "Engine " + id[^1], ["searchURLTemplate"] = template, ["suggestionURLTemplate"] = null };
        var valid = "00000000-0000-0000-0000-000000000001";
        var invalid = "00000000-0000-0000-0000-000000000002";
        JsonNode Restore(string selected) => Evaluate(new() {
            ["operation"] = "search.custom_providers",
            ["selectedID"] = selected,
            ["providers"] = new JsonArray(Stored(invalid, "http://127.0.0.1/?q=%s"), Stored(valid, "https://a.example/?q=%s"),
                Stored(valid, "https://b.example/?q=%s"))
        });
        var restored = Restore("custom:" + invalid);
        Assert.Equal("[1]", restored["indices"]!.ToJsonString());
        Assert.Equal("google", restored["selectedID"]!.GetValue<string>());
        Assert.Equal("custom:" + valid, Restore("custom:" + valid)["selectedID"]!.GetValue<string>());
        Assert.Equal("brave", Restore("brave")["selectedID"]!.GetValue<string>());
    }
}
