using System.Globalization;
using System.Text;

namespace CrestCore.Domain;

/// How a character of a domain name reads under IDNA's bidi rule (RFC 5893,
/// section 2), which groups the Unicode bidirectional classes six ways:
/// right-to-left letters (R and AL), Arabic and European numbers, nonspacing
/// marks, left-to-right letters and the neutrals the rule allows anywhere
/// (ES, CS, ET, ON and BN). Each class is read from the character's general
/// category, with the right-to-left letters and the numbers from the ranges
/// that hold them. Symbols and punctuation read as neutral, the few of them
/// that are left-to-right included; a host needs letters, digits and marks.
internal sealed class BidiClass {
    #region Static Variables

    private const string EncodedPrefix = "xn--";

    private static readonly IdnMapping Idna = new() { AllowUnassigned = true, UseStd3AsciiRules = false };

    public static readonly BidiClass Mark = new(startsRightToLeft: false, startsLeftToRight: false, inRightToLeft: true,
        inLeftToRight: true, endsRightToLeft: false, endsLeftToRight: false, isMark: true, isNumber: false,
        holds: rune => Rune.GetUnicodeCategory(rune) is UnicodeCategory.NonSpacingMark or UnicodeCategory.EnclosingMark);
    public static readonly BidiClass ArabicNumber = new(startsRightToLeft: false, startsLeftToRight: false, inRightToLeft: true,
        inLeftToRight: false, endsRightToLeft: true, endsLeftToRight: false, isMark: false, isNumber: true,
        holds: In(Ranges("0600-0605 0660-0669 066B-066C 06DD 0890-0891 08E2 10D30-10D39 10E60-10E7E")));
    public static readonly BidiClass EuropeanNumber = new(startsRightToLeft: false, startsLeftToRight: false, inRightToLeft: true,
        inLeftToRight: true, endsRightToLeft: true, endsLeftToRight: true, isMark: false, isNumber: true,
        holds: In(Ranges("0030-0039 00B2-00B3 00B9 06F0-06F9 2070 2074-2079 2080-2089 2488-249B FF10-FF19 102E1-102FB 1D7CE-1D7FF "
            + "1F100-1F10A 1FBF0-1FBF9")));
    public static readonly BidiClass RightToLeft = new(startsRightToLeft: true, startsLeftToRight: false, inRightToLeft: true,
        inLeftToRight: false, endsRightToLeft: true, endsLeftToRight: false, isMark: false, isNumber: false,
        holds: In(Ranges("05BE-05F4 0608 060B 060D 061B-064A 066D-06D5 06E5-06E6 06EE-07F5 07FA-08C9 200F FB1D-FB28 FB2A-FD3D "
            + "FD50-FDFC FE70-FEFC 10800-1091B 10920-10B35 10B40-10FF6 1E800-1EEBB")));
    public static readonly BidiClass LeftToRight = new(startsRightToLeft: false, startsLeftToRight: true, inRightToLeft: false,
        inLeftToRight: true, endsRightToLeft: false, endsLeftToRight: true, isMark: false, isNumber: false,
        holds: rune => Rune.GetUnicodeCategory(rune) is UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter
            or UnicodeCategory.TitlecaseLetter or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter
            or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.DecimalDigitNumber or UnicodeCategory.LetterNumber);
    public static readonly BidiClass Neutral = new(startsRightToLeft: false, startsLeftToRight: false, inRightToLeft: true,
        inLeftToRight: true, endsRightToLeft: false, endsLeftToRight: false, isMark: false, isNumber: false, holds: _ => true);

    /// The classes in the order a character is read: the first that holds it
    /// is its class.
    public static IReadOnlyList<BidiClass> All { get; } = [Mark, ArabicNumber, EuropeanNumber, RightToLeft, LeftToRight, Neutral];

    #endregion

    #region Variables

    /// Whether a label starting with the class reads right to left, or left
    /// to right; a label starting with neither breaks the rule.
    private readonly bool startsRightToLeft;
    private readonly bool startsLeftToRight;
    /// Whether a right-to-left, or a left-to-right, label may hold the class.
    private readonly bool inRightToLeft;
    private readonly bool inLeftToRight;
    /// Whether a right-to-left, or a left-to-right, label may end in the
    /// class, before any marks.
    private readonly bool endsRightToLeft;
    private readonly bool endsLeftToRight;
    private readonly bool isMark;
    /// Whether the class is a kind of number, of which a right-to-left label
    /// holds at most one.
    private readonly bool isNumber;
    private readonly Func<Rune, bool> holds;

    #endregion

    #region Constructors

    private BidiClass(bool startsRightToLeft, bool startsLeftToRight, bool inRightToLeft, bool inLeftToRight, bool endsRightToLeft,
        bool endsLeftToRight, bool isMark, bool isNumber, Func<Rune, bool> holds) {
        this.startsRightToLeft = startsRightToLeft;
        this.startsLeftToRight = startsLeftToRight;
        this.inRightToLeft = inRightToLeft;
        this.inLeftToRight = inLeftToRight;
        this.endsRightToLeft = endsRightToLeft;
        this.endsLeftToRight = endsLeftToRight;
        this.isMark = isMark;
        this.isNumber = isNumber;
        this.holds = holds;
    }

    #endregion

    #region Actions - Hosts

    /// Whether `host`, a domain name, meets the bidi rule, as the URL
    /// standard requires of every host: a name holding right-to-left text or
    /// an Arabic number has each label read in one direction, starting and
    /// ending as that direction allows. A name without such text meets it. An
    /// `xn--` label is read as the Unicode it encodes, and one that encodes
    /// none as written.
    public static bool AllowsHost(string host) {
        ArgumentNullException.ThrowIfNull(host);
        var labels = host.Split('.').Where(label => label.Length > 0)
            .Select(label => Unicode(label).EnumerateRunes().Select(Of).ToArray()).ToArray();
        return !labels.Any(label => label.Any(character => !character.inLeftToRight)) || labels.All(Allows);
    }

    /// The class of `rune`.
    public static BidiClass Of(Rune rune) => All.First(bidi => bidi.holds(rune));

    /// Whether one label of a name holding right-to-left text meets the rule.
    private static bool Allows(BidiClass[] label) {
        bool rightToLeft = label[0].startsRightToLeft;
        if (!rightToLeft && !label[0].startsLeftToRight) return false;
        if (!label.All(character => rightToLeft ? character.inRightToLeft : character.inLeftToRight)) return false;
        var last = label.Last(character => !character.isMark);
        if (!(rightToLeft ? last.endsRightToLeft : last.endsLeftToRight)) return false;
        return !rightToLeft || label.Where(character => character.isNumber).Distinct().Count() <= 1;
    }

    /// `label` in Unicode: an `xn--` label decoded, any other as written.
    private static string Unicode(string label) {
        if (!label.StartsWith(EncodedPrefix, StringComparison.OrdinalIgnoreCase)) return label;
        try {
            return Idna.GetUnicode(label);
        } catch (ArgumentException) {
            return label;
        }
    }

    #endregion

    #region Actions - Ranges

    /// Whether a character falls in one of `ranges`.
    private static Func<Rune, bool> In(IReadOnlyList<(int First, int Last)> ranges) =>
        rune => ranges.Any(range => rune.Value >= range.First && rune.Value <= range.Last);

    /// The code point ranges `spelled` lists: hexadecimal code points or
    /// `first-last` ranges, separated by spaces.
    private static IReadOnlyList<(int First, int Last)> Ranges(string spelled) => [.. spelled.Split(' ').Select(range => {
        string[] ends = range.Split('-');
        return (int.Parse(ends[0], NumberStyles.HexNumber, CultureInfo.InvariantCulture),
            int.Parse(ends[^1], NumberStyles.HexNumber, CultureInfo.InvariantCulture));
    })];

    #endregion
}
