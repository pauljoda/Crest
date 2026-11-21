using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The rule among `Rules` that applies to pages in `SourceLanguage`, whose
/// region aliases share it, the language such pages are translated into, and
/// whether such a page is offered translation: when a rule translates it, or
/// its language is not `PreferredLanguage`, the person's first language, else
/// `FallbackPreferredLanguage`. A language written in another script, as
/// Traditional Chinese is for a reader of Simplified, counts as another. It
/// reads no state, so a host may ask it without an app.
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
        bool offers = target is not null || !LanguageTag.Matches(SourceLanguage, PreferredLanguage ?? FallbackPreferredLanguage);
        return new(rules.Rule(SourceLanguage), target, offers);
    }

    #endregion
}
