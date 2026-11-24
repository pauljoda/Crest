using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace CrestCore.Domain;

/// Text as autofill compares it: in lowercase, without diacritics, with `ß`
/// spelled `ss`, and every run of characters other than letters and digits
/// one space. A page's names for a field also split where a lowercase letter
/// meets a capital, so `billingPostalCode` reads `billing postal code`.
internal sealed record FoldedText {
    #region Static Variables

    /// The most characters of one text autofill reads.
    private const int MaximumCharacters = 256;

    #endregion

    #region Variables

    public string Value { get; }

    public bool IsEmpty => Value.Length == 0;

    /// Whether the text is only digits.
    public bool IsNumber => Value.Length > 0 && Value.All(char.IsAsciiDigit);

    #endregion

    #region Constructors

    private FoldedText(string value) {
        Value = value;
    }

    #endregion

    #region Actions - Folding

    /// `text` folded for comparison.
    public static FoldedText Of(string? text) => new(Fold(text, splitsWords: false));

    /// A page's name for a field folded for comparison, split into its words.
    public static FoldedText OfName(string? text) => new(Fold(text, splitsWords: true));

    private static string Fold(string? text, bool splitsWords) {
        if (string.IsNullOrEmpty(text)) return "";
        string source = text.Length > MaximumCharacters ? text[..MaximumCharacters] : text;
        var spaced = new StringBuilder(source.Length + 8);
        for (int index = 0; index < source.Length; index++) {
            if (splitsWords && index > 0 && StartsWord(source, index)) spaced.Append(' ');
            spaced.Append(source[index]);
        }
        var folded = new StringBuilder(spaced.Length);
        bool separated = false;
        foreach (char character in spaced.ToString().Normalize(NormalizationForm.FormD)) {
            if (CharUnicodeInfo.GetUnicodeCategory(character) == UnicodeCategory.NonSpacingMark) continue;
            if (!char.IsLetterOrDigit(character)) {
                separated = true;
                continue;
            }
            if (separated && folded.Length > 0) folded.Append(' ');
            separated = false;
            char lower = char.ToLowerInvariant(character);
            folded.Append(Unjoined(lower) ?? lower.ToString());
        }
        return folded.ToString();
    }

    /// Whether the capital at `index` starts a word: it follows a lowercase
    /// letter, or ends a run of capitals before a lowercase letter.
    private static bool StartsWord(string text, int index) =>
        char.IsUpper(text[index])
        && (char.IsLower(text[index - 1])
            || char.IsUpper(text[index - 1]) && index + 1 < text.Length && char.IsLower(text[index + 1]));

    /// The letters a letter that does not decompose is spelled with.
    private static string? Unjoined(char letter) => letter switch {
        'ß' => "ss",
        'æ' => "ae",
        'œ' => "oe",
        'ø' => "o",
        'ł' => "l",
        'đ' => "d",
        'ı' => "i",
        _ => null
    };

    #endregion

    #region Actions - Comparing

    /// Whether the text holds `words` as a run of whole words.
    public bool HoldsWords(FoldedText words) =>
        !words.IsEmpty && $" {Value} ".Contains($" {words.Value} ", StringComparison.Ordinal);

    public bool Matches(Regex pattern) => pattern.IsMatch(Value);

    #endregion
}
