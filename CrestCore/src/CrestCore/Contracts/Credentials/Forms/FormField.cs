using System.Text.RegularExpressions;

namespace CrestCore.Contracts;

/// One input of a form as Crest's page script describes it, without its value.
/// `Index` is its place in the script's reading of the form, the reference a
/// fill and a capture name it by. `Autocomplete` is the attribute as the page
/// wrote it, and `Name`, `IdAttribute`, `Label` and `Placeholder` are what the
/// page calls the field. `EnteredByPerson` is true when the person typed,
/// pasted or dictated the value, or chose a password Crest made for the field;
/// a value the page or an extension put there is not theirs. `MinLength`,
/// `MaxLength` and `PasswordRules` are the field's own limits for a new password.
public sealed record FormField(int Index, FormInputType InputType, string Autocomplete, string Name, string IdAttribute,
    string Label, string Placeholder, bool IsVisible, bool HasValue, bool EnteredByPerson, int? MinLength, int? MaxLength,
    string? PasswordRules) {
    #region Variables

    /// The limits a password Crest makes for this field has to meet.
    internal PasswordRequirements Requirements => new(MinLength, MaxLength, PasswordRules);

    #endregion

    #region Actions - Reading

    /// Whether the page's autocomplete attribute names `token`.
    internal bool Declares(string token) =>
        Autocomplete.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Any(declared => string.Equals(declared, token, StringComparison.OrdinalIgnoreCase));

    /// Whether anything the page calls the field matches `pattern`.
    internal bool IsCalled(Regex pattern) =>
        pattern.IsMatch(Name) || pattern.IsMatch(IdAttribute) || pattern.IsMatch(Label) || pattern.IsMatch(Placeholder);

    #endregion
}
