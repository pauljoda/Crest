using CrestCore.Domain;

namespace CrestCore.Contracts;

/// How address and card autofill reads a field and chooses what to write
/// into it.
public sealed partial record FormField {
    #region Static Variables

    /// The fewest of a select's options that must name months for it to be
    /// read as a month, and years for it to be read as a year.
    private const int MinimumMonthChoices = 12;

    private const int MinimumYearChoices = 3;

    #endregion

    #region Variables

    /// Whether address and card autofill reads the field: a visible one of a
    /// type it writes into.
    internal bool TakesAutofill => IsVisible && InputType.TakesAutofill;

    /// What the page calls the field: its name, identifier, label and
    /// placeholder, each folded for comparison.
    internal IReadOnlyList<FoldedText> FoldedNames =>
        [FoldedText.OfName(Name), FoldedText.OfName(IdAttribute), FoldedText.OfName(Label), FoldedText.OfName(Placeholder)];

    /// Whether the field is a select whose options name the months, by their
    /// value, their text or a word of it, as `01 - January` does.
    internal bool ChoosesMonth => InputType.OffersChoices
        && Options.Count(option => CalendarMonth.Named(option.Value) is not null
            || FoldedText.Of(option.Text).Value.Split(' ').Prepend(option.Text).Any(word => CalendarMonth.Named(word) is not null))
            >= MinimumMonthChoices;

    /// Whether the field is a select whose options name years.
    internal bool ChoosesYear => InputType.OffersChoices && !ChoosesMonth
        && Options.Count(option => ExpiryFormat.Year(option.Value) is not null || ExpiryFormat.Year(option.Text) is not null)
            >= MinimumYearChoices;

    #endregion

    #region Actions - Autofill

    /// What a fill writes into the field from `spellings`, the ways of
    /// writing one value in order of preference, or null for nothing. A
    /// select takes the `Value` of the option one of them names (see
    /// `ChoiceFor`); any other field the first spelling that fits its maximum
    /// length, or the first spelling when none fits.
    internal string? Fill(IEnumerable<string?> spellings) {
        var wanted = spellings.OfType<string>().Where(spelling => !string.IsNullOrWhiteSpace(spelling)).Distinct(StringComparer.Ordinal)
            .ToList();
        if (wanted.Count == 0) return null;
        if (InputType.OffersChoices) return ChoiceFor(wanted)?.Value;
        return wanted.FirstOrDefault(spelling => MaxLength is not int maximum || spelling.Length <= maximum) ?? wanted[0];
    }

    /// The option the first of `spellings` that can names: one whose value or
    /// text is the spelling, ignoring case and diacritics, or else the only
    /// option whose text holds it as whole words, for a spelling of digits or
    /// of at least three characters, so `01` finds `01 - January` and a code
    /// of two letters finds only an option it is all of.
    private FormOption? ChoiceFor(IReadOnlyList<string> spellings) {
        var folded = spellings.Select(FoldedText.Of).Where(spelling => !spelling.IsEmpty).Distinct().ToList();
        var options = Options.Select(option => (Option: option, Value: FoldedText.Of(option.Value), Text: FoldedText.Of(option.Text))).ToList();
        foreach (var spelling in folded) {
            if (options.FirstOrDefault(option => option.Value == spelling || option.Text == spelling).Option is { } exact) return exact;
        }
        foreach (var spelling in folded.Where(spelling => spelling.IsNumber || spelling.Value.Length >= 3)) {
            var holding = options.Where(option => option.Text.HoldsWords(spelling)).Take(2).ToList();
            if (holding.Count == 1) return holding[0].Option;
        }
        return null;
    }

    /// What a value the form sent from this field may be read as: for a
    /// select, the text of the option it holds, then the value itself.
    internal IReadOnlyList<string> SpellingsOf(string value) {
        ArgumentNullException.ThrowIfNull(value);
        string? text = InputType.OffersChoices ? Options.FirstOrDefault(option => option.Value == value)?.Text : null;
        return [.. new[] { text, value }.OfType<string>().Select(spelling => spelling.Trim()).Where(spelling => spelling.Length > 0)
            .Distinct(StringComparer.Ordinal)];
    }

    #endregion
}
