namespace CrestCore.Contracts;

/// Crest's bundled Balanced protection, as a content rule list to compile.
public sealed record BalancedProtectionRules() : Query<ContentRuleList>;
