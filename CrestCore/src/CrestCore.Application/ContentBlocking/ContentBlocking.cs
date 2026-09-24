using CrestCore.Contracts;

namespace CrestCore.Application;

/// The content-blocking area: Crest's bundled rule lists, in the WebKit
/// content-rule format the platform's rule-list store compiles.
public sealed class ContentBlocking {
    #region Actions - Rule lists

    public ContentRuleList Answer(BalancedProtectionRules query) {
        ArgumentNullException.ThrowIfNull(query);
        return ContentBlockingPolicy.Balanced.RuleList()
            ?? throw new InvalidOperationException("Balanced protection always has a rule list.");
    }

    #endregion
}
