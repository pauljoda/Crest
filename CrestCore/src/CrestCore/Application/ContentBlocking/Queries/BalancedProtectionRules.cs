using CrestCore.Application;

namespace CrestCore.Contracts;

/// Crest's bundled Balanced protection, as a content rule list to compile.
[MessageLimit(5 * 1024 * 1024)]
public sealed record BalancedProtectionRules(byte[]? Snapshot = null) : Query<ContentRuleList> {
    #region Actions - Answering

    internal override ContentRuleList Answer(CrestApp app) {
        return Snapshot is { } snapshot ? ContentRuleList.FromArchive(snapshot) : ContentBlockingPolicy.Balanced.RuleList()
            ?? throw new InvalidOperationException("Balanced protection always has a rule list.");
    }

    #endregion
}
