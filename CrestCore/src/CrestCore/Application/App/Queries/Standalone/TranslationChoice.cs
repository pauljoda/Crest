using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The rule among `Rules` that applies to pages in `SourceLanguage`, whose
/// region aliases share it, the language such pages are translated into, and
/// whether such a page is offered translation: when a rule translates it, or
/// its language is not `PreferredLanguage`, the person's first language, else
/// `FallbackPreferredLanguage`. It reads no state, so a host may ask it
/// without an app.
public sealed record TranslationChoice(IReadOnlyList<TranslationRule> Rules, string SourceLanguage, string? PreferredLanguage = null)
    : StandaloneQuery<TranslationDecision> {
    #region Static Variables

    /// The language a person who names none reads.
    public const string FallbackPreferredLanguage = "en";

    #endregion

    #region Actions - Answering

    internal override TranslationDecision Answer(StandaloneContext context) {
        var rules = AutomaticTranslationRules.Restore(Rules);
        var target = rules.Target(SourceLanguage);
        bool offers = target is not null || !SameLanguage(SourceLanguage, PreferredLanguage ?? FallbackPreferredLanguage);
        return new(rules.Rule(SourceLanguage), target, offers);
    }

    /// Whether two language tags name one language, whatever region or script
    /// they add.
    private static bool SameLanguage(string first, string second) =>
        string.Equals(PrimaryLanguage(first), PrimaryLanguage(second), StringComparison.OrdinalIgnoreCase);

    /// The language a tag names, without its script or region.
    private static string PrimaryLanguage(string tag) => tag.Split('-', '_')[0];

    #endregion
}
