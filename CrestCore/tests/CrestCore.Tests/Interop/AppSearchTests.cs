using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

using CrestCore.Contracts;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// Balanced protection through the encoded native boundary.
public sealed class AppSearchTests {
    #region Actions - Rules

    [Fact]
    public void BalancedProtectionProvidesNativeNetworkAndCosmeticRulesWithoutBlockingDocuments() {
        using var app = new AppClient();
        var list = app.Ask(new BalancedProtectionRules(), ContractCodec.ReadContentRuleList);
        var rules = JsonNode.Parse(list.Source)!.AsArray();
        Assert.Null(ContentBlockingPolicy.Off.RuleList());
        Assert.True(list.Version > 0);
        Assert.Equal(ContentBlockingPolicy.Balanced.Identifier, list.Identifier);
        var blocks = rules.Where(rule => rule!["action"]!["type"]!.GetValue<string>() == "block").ToArray();
        Assert.NotEmpty(blocks);
        Assert.All(blocks, rule => Assert.DoesNotContain("document",
            rule!["trigger"]!["resource-type"]!.AsArray().Select(value => value!.GetValue<string>())));
        Assert.Contains(blocks, rule => Regex.IsMatch("https://googleads.g.doubleclick.net/pagead/ads",
            rule!["trigger"]!["url-filter"]!.GetValue<string>(), RegexOptions.None, TimeSpan.FromSeconds(1)));
        Assert.Contains(rules, rule => rule!["action"]!["type"]!.GetValue<string>() == "css-display-none");
        Assert.Contains(rules, rule => rule!["action"]!["type"]!.GetValue<string>() == "ignore-previous-rules");
        var recovery = rules.Last()!;
        Assert.Equal("block", recovery["action"]!["type"]!.GetValue<string>());
        Assert.Equal("third-party", recovery["trigger"]!["load-type"]![0]!.GetValue<string>());
        Assert.True(Regex.IsMatch("https://fundingchoicesmessages.google.com/recovery",
            recovery["trigger"]!["url-filter"]!.GetValue<string>(), RegexOptions.None, TimeSpan.FromSeconds(1)));
    }

    #endregion
}
