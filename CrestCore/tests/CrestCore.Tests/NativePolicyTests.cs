using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed class NativePolicyTests
{
    [Theory]
    [InlineData("apple.com", "https://apple.com", null)]
    [InlineData("localhost:3000", "http://localhost:3000", null)]
    [InlineData("https://webkit.org/blog/", "https://webkit.org/blog/", null)]
    [InlineData("  Café + Swift/URL & WebKit  ", "https://kagi.com/search?q=Caf%C3%A9%20%2B%20Swift%2FURL%20%26%20WebKit", "Café + Swift/URL & WebKit")]
    [InlineData("   ", null, null)]
    public void ExistingAddressCallSitesKeepTheirIntentAndURLSpelling(string input, string? url, string? query)
    {
        var bytes = Encoding.UTF8.GetBytes(new JsonObject
        { ["version"] = 1, ["operation"] = "address.intent", ["input"] = input, ["searchTemplate"] = "https://kagi.com/search?q=%s" }.ToJsonString());
        var result = NativePolicyEvaluator.Evaluate(bytes);
        Assert.Equal(result, NativePolicyEvaluator.Evaluate(bytes));
        var values = JsonNode.Parse(result)!;
        Assert.Equal(url, values["url"]?.GetValue<string>());
        Assert.Equal(query, values["searchQuery"]?.GetValue<string>());
    }
    [Theory]
    [InlineData("chrome://extensions/")]
    [InlineData("crest://extensions/?id=abcdefghijklmnopabcdefghijklmnop#details")]
    [InlineData("CREST://version/")]
    [InlineData("chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html")]
    public void InternalAddressesRequireTheSelectedEngineCapability(string address)
    {
        var request = new JsonObject { ["version"] = 1, ["operation"] = "address.intent", ["input"] = address,
            ["searchTemplate"] = "https://kagi.com/search?q=%s" };
        var disabled = JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
        Assert.Equal(address, disabled["searchQuery"]!.GetValue<string>());
        request["allowsInternalPages"] = true;
        var enabled = JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
        Assert.Equal(address, enabled["url"]!.GetValue<string>());
        Assert.Null(enabled["searchQuery"]);
    }
    [Fact]
    public void LinkPolicyWireContractAcceptsNullableContextAndRejectsExtraInstructions()
    {
        var request = new JsonObject { ["version"] = 1, ["operation"] = "navigation.link", ["url"] = "https://example.com/",
            ["userActivatedLink"] = true, ["topLevel"] = true, ["peekModified"] = false, ["newTabModified"] = true,
            ["shiftModified"] = true, ["focusesNewTabs"] = false, ["hasContext"] = false, ["placement"] = null,
            ["savedUrl"] = null, ["automaticallyOpensPeek"] = false };
        var response = JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
        Assert.Equal("foregroundTab", response["decision"]!.GetValue<string>());
        request["engineCommand"] = "navigate";
        Assert.Throws<ProtocolException>(() => NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())));
    }
    [Fact]
    public void ModifiedLinkWireKeepsPreferenceAndOwnershipExplicit()
    {
        var request = new JsonObject { ["version"] = 1, ["operation"] = "navigation.modified_link", ["url"] = "https://example.com/",
            ["userActivatedLink"] = true, ["topLevel"] = true, ["commandModified"] = true, ["optionModified"] = false,
            ["middleClick"] = false, ["peekModifier"] = "command", ["shiftModified"] = false,
            ["focusesNewTabs"] = false, ["hasContext"] = true, ["placement"] = "open", ["savedUrl"] = null,
            ["automaticallyOpensPeek"] = false };
        string Decision() => JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!["decision"]!.GetValue<string>();
        Assert.Equal("peekModifier", Decision());
        request["hasContext"] = false;
        Assert.Equal("navigate", Decision());
        request["peekModifier"] = "option";
        Assert.Equal("backgroundTab", Decision());
        request["shiftModified"] = true;
        Assert.Equal("foregroundTab", Decision());
        request["peekModifier"] = "control";
        Assert.Throws<ProtocolException>(() => Decision());
        request["peekModifier"] = "option";
        request["peekModified"] = true;
        Assert.Throws<ProtocolException>(() => Decision());
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
        Assert.Throws<BrowserRuleException>(() => SearchPreferences.Default.Resolve("https://user:password@example.org", false));
    }

    [Fact]
    public void PurePolicyRejectsUnknownVersionsAndOperations()
    {
        Assert.Throws<ProtocolException>(() => NativePolicyEvaluator.Evaluate("{\"version\":2,\"operation\":\"address.intent\"}"u8));
        Assert.Throws<ProtocolException>(() => NativePolicyEvaluator.Evaluate("{\"version\":1,\"operation\":\"native.invoke\"}"u8));
        Assert.Throws<ProtocolException>(() => NativePolicyEvaluator.Evaluate(new byte[NativePolicyEvaluator.MaximumInputBytes + 1]));
    }
    [Fact]
    public void RetentionAndExplicitDeletionKeepTheirDifferentBoundaryRules()
    {
        // Retention excludes an exact cutoff and future records. Explicit
        // deletion includes its start and excludes its end.
        var expiry = JsonNode.Parse(NativePolicyEvaluator.Evaluate(
            "{\"version\":1,\"operation\":\"records.expired\",\"timestamps\":[9,10,11,21],\"now\":20,\"lifetime\":10}"u8))!;
        Assert.Equal("[0]", expiry["indices"]!.ToJsonString());
        var range = JsonNode.Parse(NativePolicyEvaluator.Evaluate(
            "{\"version\":1,\"operation\":\"history.remove_range\",\"timestamps\":[9,10,11,20],\"start\":10,\"end\":20}"u8))!;
        Assert.Equal("[1,2]", range["indices"]!.ToJsonString());
        var reversed = JsonNode.Parse(NativePolicyEvaluator.Evaluate(
            "{\"version\":1,\"operation\":\"history.remove_range\",\"timestamps\":[10],\"start\":20,\"end\":10}"u8))!;
        Assert.Empty(reversed["indices"]!.AsArray());
    }
}
