using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// Custom search engines and Balanced protection through the native app
/// boundary: encoded queries in, encoded answers or one rejection out.
public sealed class AppSearchTests {
    [Fact]
    public void CustomEngineAdmissionAnswersTheSavedEngineOrTheRuleItBreaks() {
        using var app = new AppClient();
        var id = Guid.NewGuid();
        var typed = new CustomSearchEngine(id, "  Kagi ", " https://kagi.com/search?q=%s ", " ");
        Assert.Equal(new CustomSearchEngine(id, "Kagi", "https://kagi.com/search?q=%s", null),
            app.Ask(new CustomSearchEngineAdmission(typed, []), ContractCodec.ReadCustomSearchEngine));
        Assert.Equal(new InvalidSearchEngine(SearchEngineFlaw.RequiresHttps),
            app.Refuse(new CustomSearchEngineAdmission(typed with { SearchTemplate = "http://kagi.com/?q=%s" }, [])));
        Assert.Equal(new DuplicateSearchEngineName(),
            app.Refuse(new CustomSearchEngineAdmission(typed, [typed with { Id = Guid.NewGuid(), Name = "KAGI" }])));
    }

    [Fact]
    public void BalancedProtectionBlocksThirdPartyLoadsFromEveryListedHostAndItsSubdomains() {
        using var app = new AppClient();
        var list = app.Ask(new BalancedProtectionRules(), ContractCodec.ReadContentRuleList);
        Assert.Equal("com.pauldavis.crest.content-blocking.balanced.v2", list.Identifier);
        var rules = JsonNode.Parse(list.Source)!.AsArray();
        Assert.Equal(ContentBlockingPolicy.Balanced.BlockedHostSuffixes.Count, rules.Count);
        Assert.Null(ContentBlockingPolicy.Off.RuleList());
        var trigger = rules[0]!["trigger"]!;
        Assert.Equal(@"^[^:]+://+([^:/]+\.)?doubleclick\.net[:/]", trigger["url-filter"]!.GetValue<string>());
        Assert.Equal(["third-party"], trigger["load-type"]!.AsArray().Select(value => value!.GetValue<string>()));
        Assert.DoesNotContain("document", trigger["resource-type"]!.AsArray().Select(value => value!.GetValue<string>()));
        Assert.All(rules, rule => Assert.Equal("block", rule!["action"]!["type"]!.GetValue<string>()));
    }
}
