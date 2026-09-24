namespace CrestCore.Contracts;

/// Translation rules already cover `Limit` source languages.
public sealed record TranslationRuleLimitReached(int Limit) : Rejection;
