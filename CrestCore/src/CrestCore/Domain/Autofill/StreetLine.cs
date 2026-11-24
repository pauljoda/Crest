using System.Text.RegularExpressions;

namespace CrestCore.Domain;

/// The first line of a street address in the two parts a form with a house
/// number field asks for: the street and the number on it. The number may
/// follow the street, as in `Hauptstraße 5a`, or lead it, as in
/// `12 Main Street`; a line without one is all street.
internal sealed record StreetLine(string Street, string HouseNumber) {
    #region Static Variables

    /// A house number: digits, perhaps a letter, perhaps a range or a unit
    /// after a dash or slash.
    private const string Number = @"\d+\s?[a-z]?(?:\s?[-/]\s?\d+\s?[a-z]?)?";

    private static readonly Regex Trailing = new($@"^(?<street>.*\D)\s*,?\s+(?<number>{Number})$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    private static readonly Regex Leading = new($@"^(?<number>{Number})\s*,?\s+(?<street>\D.*)$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    #endregion

    #region Actions - Reading

    /// `line` split into its street and house number.
    public static StreetLine Split(string line) {
        ArgumentNullException.ThrowIfNull(line);
        string trimmed = line.Trim();
        var match = Trailing.Match(trimmed) is { Success: true } trailing ? trailing : Leading.Match(trimmed);
        return match.Success ? new(match.Groups["street"].Value.Trim(), match.Groups["number"].Value.Trim()) : new(trimmed, "");
    }

    /// The street and the number as one line, the number after the street.
    public static string Joined(string street, string houseNumber) =>
        string.Join(' ', new[] { street.Trim(), houseNumber.Trim() }.Where(part => part.Length > 0));

    #endregion
}
