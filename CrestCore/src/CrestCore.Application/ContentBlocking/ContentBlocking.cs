using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The content-blocking area: Crest's bundled rule lists, in the WebKit
/// content-rule format the platform's rule-list store compiles.
public sealed class ContentBlocking {
    #region Actions - Rule lists

    public ContentRuleList Answer(BalancedProtectionRules query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(BalancedContentBlocking.Identifier, BalancedRuleSource());
    }

    /// Every listed host and its subdomains, blocked for third-party network
    /// loads of every resource type but the top-level document.
    private static string BalancedRuleSource() => new JsonArray(BalancedContentBlocking.BlockedHostSuffixes.Select(host =>
        (JsonNode)new JsonObject {
            ["trigger"] = new JsonObject {
                ["url-filter"] = BalancedContentBlocking.UrlFilter(host),
                ["url-filter-is-case-sensitive"] = true,
                ["load-type"] = new JsonArray("third-party"),
                ["resource-type"] = new JsonArray(BalancedContentBlocking.NetworkResourceTypes
                    .Select(type => (JsonNode?)JsonValue.Create(type)).ToArray())
            },
            ["action"] = new JsonObject { ["type"] = "block" }
        }).ToArray()).ToJsonString();

    #endregion
}
