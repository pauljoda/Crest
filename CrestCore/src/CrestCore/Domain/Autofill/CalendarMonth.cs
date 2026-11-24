using System.Globalization;

namespace CrestCore.Domain;

/// A month of the year as forms spell it: its number, with and without a
/// leading zero, and its full and short names in English, German, French,
/// Spanish, Italian, Dutch and Portuguese. The core carries its own names,
/// since it runs without the system's locale data.
internal sealed class CalendarMonth {
    #region Static Variables

    /// Each month's names, in the order of the year, separated by bars.
    private static readonly string[] Rows = [
        "January|Jan|Januar|Jänner|janvier|janv|enero|ene|gennaio|gen|januari|janeiro",
        "February|Feb|Februar|février|févr|fév|febrero|febbraio|februari|fevereiro|fev",
        "March|Mar|März|Mär|Mrz|mars|marzo|maart|mrt|março",
        "April|Apr|avril|avr|abril|abr|aprile",
        "May|Mai|mayo|maggio|mag|mei|maio",
        "June|Jun|Juni|juin|junio|giugno|giu|junho",
        "July|Jul|Juli|juillet|juil|julio|luglio|lug|julho",
        "August|Aug|août|agosto|ago|augustus",
        "September|Sep|Sept|septembre|septiembre|setiembre|settembre|set|setembro",
        "October|Oct|Oktober|Okt|octobre|octubre|ottobre|ott|outubro|out",
        "November|Nov|novembre|noviembre|novembro",
        "December|Dec|Dezember|Dez|décembre|déc|diciembre|dic|dicembre|dezembro"
    ];

    public static IReadOnlyList<CalendarMonth> All { get; } = [.. Rows.Select((row, index) => new CalendarMonth(index + 1, row.Split('|')))];

    #endregion

    #region Variables

    /// The month's number, 1 for January.
    public int Number { get; }

    /// What a form may spell the month with: its number with a leading zero,
    /// without one, then its names.
    public IReadOnlyList<string> Spellings { get; }

    /// Its spellings folded for comparison.
    private readonly IReadOnlyList<FoldedText> folded;

    #endregion

    #region Constructors

    private CalendarMonth(int number, string[] names) {
        Number = number;
        string digits = number.ToString(CultureInfo.InvariantCulture);
        Spellings = number < 10 ? [$"0{digits}", digits, .. names] : [digits, .. names];
        folded = [.. Spellings.Select(FoldedText.Of)];
    }

    #endregion

    #region Actions - Lookup

    /// The month numbered `number`, or null when it is not 1 to 12.
    public static CalendarMonth? Numbered(int number) => number is >= 1 and <= 12 ? All[number - 1] : null;

    /// The month `text` names: its number or one of its names, in any case and
    /// with or without diacritics.
    public static CalendarMonth? Named(string? text) {
        var wanted = FoldedText.Of(text);
        if (wanted.IsNumber) return int.TryParse(wanted.Value, NumberStyles.None, CultureInfo.InvariantCulture, out int number) ? Numbered(number) : null;
        return wanted.IsEmpty ? null : All.FirstOrDefault(month => month.folded.Contains(wanted));
    }

    #endregion
}
