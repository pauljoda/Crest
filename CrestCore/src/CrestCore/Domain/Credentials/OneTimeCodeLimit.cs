using System.Globalization;

namespace CrestCore.Domain;

/// The values a one-time code's length or period may take, from `Shortest`
/// to `Longest`, and the one a setup that names none takes.
internal sealed record OneTimeCodeLimit(int Shortest, int Longest, int Default) {
    #region Variables

    /// Whether the limit allows only one value, which a setup then takes
    /// whatever it names.
    private bool IsFixed => Shortest == Longest;

    #endregion

    #region Actions - Reading

    /// Whether `value` is within the limit.
    public bool Admits(int value) => value >= Shortest && value <= Longest;

    /// The value a link's parameter `text` names: the default when it names
    /// none or the limit allows only one, its number when the limit admits it,
    /// and otherwise null.
    public int? Read(string? text) {
        if (text is null || IsFixed) return Default;
        return int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out int value) && Admits(value) ? value : null;
    }

    #endregion
}
