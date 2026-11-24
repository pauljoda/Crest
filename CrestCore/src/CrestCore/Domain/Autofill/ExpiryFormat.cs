using System.Globalization;
using System.Text.RegularExpressions;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// How a field spells a card's expiry: the month in two digits, then
/// `Separator`, then the year in `YearDigits`, two or four. A field shows its
/// format in its placeholder or label, such as `MM / YY`, or `MM/JJ` and
/// `MM/AA` where the year is Jahr, année or año, and otherwise its maximum
/// length suggests one.
internal sealed record ExpiryFormat(string Separator, int YearDigits) {
    #region Static Variables

    /// The format a field that shows none takes.
    public static ExpiryFormat Common { get; } = new("/", 2);

    /// The formats fields of each maximum length take.
    private static readonly IReadOnlyList<(int Length, ExpiryFormat Format)> Sized =
        [(4, new("", 2)), (5, new("/", 2)), (6, new("", 4)), (7, new("/", 4))];

    /// Every format a select's options may spell an expiry with.
    public static IReadOnlyList<ExpiryFormat> Spelled { get; } = [Common, new("/", 4), new(" / ", 2), new("-", 2), new("", 2)];

    /// A month and year as a placeholder or label shows them.
    private static readonly Regex Shown = new(@"\bmm?(?<separator>\s*[/\-.]?\s*)(?<year>(?:yy|jj|aa){1,2})\b",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// A year alone as a placeholder or label shows it.
    private static readonly Regex ShownYear = new(@"^\s*(?<year>(?:yy|jj|aa){1,2})\s*$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// An expiry as a person types it: a month, perhaps a separator, then a
    /// year of two or four digits.
    private static readonly Regex Typed = new(@"^\s*(?<month>\d{1,2})\s*[/\-. ]?\s*(?<year>\d{4}|\d{2})\s*$", RegexOptions.CultureInvariant);

    /// An expiry as a month field holds it: the year, a dash, then the month.
    private static readonly Regex Monthly = new(@"^\s*(?<year>\d{4})-(?<month>\d{2})\s*$", RegexOptions.CultureInvariant);

    #endregion

    #region Actions - Reading

    /// The format `field` shows or its maximum length suggests, or `Common`.
    public static ExpiryFormat Of(FormField field) {
        ArgumentNullException.ThrowIfNull(field);
        return Shown.Match(field.Placeholder) is { Success: true } placeholder ? Read(placeholder)
            : Shown.Match(field.Label) is { Success: true } label ? Read(label)
            : Sized.Where(size => size.Length == field.MaxLength).Select(size => size.Format).FirstOrDefault() ?? Common;
    }

    /// The digits of the year a year field takes: those its placeholder or
    /// label shows, two when it holds at most two characters, or else four.
    public static int YearDigitsOf(FormField field) {
        ArgumentNullException.ThrowIfNull(field);
        if (ShownYear.Match(field.Placeholder) is { Success: true } placeholder) return placeholder.Groups["year"].Length;
        if (ShownYear.Match(field.Label) is { Success: true } label) return label.Groups["year"].Length;
        return field.MaxLength is <= 2 ? 2 : 4;
    }

    /// The month and four-digit year `text` spells, as a person types an
    /// expiry or a month field holds one, or null.
    public static (int Month, int Year)? Parse(string? text) {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var match = Typed.Match(text) is { Success: true } typed ? typed : Monthly.Match(text);
        if (!match.Success) return null;
        int month = int.Parse(match.Groups["month"].Value, CultureInfo.InvariantCulture);
        return month is >= 1 and <= 12 && Year(match.Groups["year"].Value) is int year ? (month, year) : null;
    }

    /// The four-digit year `text` spells in two or four digits, or null.
    public static int? Year(string? text) {
        string digits = text?.Trim() ?? "";
        if (digits.Length is not (2 or 4) || !digits.All(char.IsAsciiDigit)) return null;
        int year = int.Parse(digits, CultureInfo.InvariantCulture);
        return digits.Length == 2 ? 2000 + year : year;
    }

    private static ExpiryFormat Read(Match match) => new(match.Groups["separator"].Value, match.Groups["year"].Length);

    #endregion

    #region Actions - Spelling

    /// The expiry `month` of `year` in this format.
    public string Spell(int month, int year) =>
        string.Create(CultureInfo.InvariantCulture, $"{month:00}{Separator}{(YearDigits == 2 ? year % 100 : year):00}");

    /// The year `year` in `digits` digits.
    public static string SpellYear(int year, int digits) =>
        (digits == 2 ? year % 100 : year).ToString(digits == 2 ? "00" : "0000", CultureInfo.InvariantCulture);

    #endregion
}
