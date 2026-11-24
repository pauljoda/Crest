namespace CrestCore.Domain;

/// A field's `autocomplete` attribute as the HTML standard reads it: an
/// optional `section-*` token, an optional `shipping` or `billing`, an
/// optional kind of contact such as `work`, then the field's name, and an
/// optional `webauthn`. `Scope` is the section token and the shipping or
/// billing mode together, null when the page states neither, and `FieldName`
/// the field's name, null when the attribute names none, as `on` and `off` do.
internal sealed record AutocompleteAttribute(string? Scope, string? FieldName) {
    #region Static Variables

    private const string SectionPrefix = "section-";

    private static readonly string[] Modes = ["shipping", "billing"];

    private static readonly string[] Contacts = ["home", "work", "mobile", "fax", "pager"];

    private static readonly string[] Unnamed = ["on", "off", "webauthn"];

    /// The field names the standard defines that address and card autofill
    /// leaves alone: a page that declares one says the field holds something
    /// else, such as a password, a birthday or part of a phone number.
    private static readonly string[] OtherFieldNames = [
        "honorific-prefix", "honorific-suffix", "nickname", "username", "new-password", "current-password", "one-time-code",
        "organization-title", "address-level3", "address-level4", "cc-additional-name", "cc-type", "transaction-currency",
        "transaction-amount", "language", "bday", "bday-day", "bday-month", "bday-year", "sex", "url", "photo",
        "tel-country-code", "tel-national", "tel-area-code", "tel-local", "tel-local-prefix", "tel-local-suffix",
        "tel-extension", "impp"
    ];

    #endregion

    #region Variables

    /// Whether the attribute names a field that address and card autofill
    /// leaves alone.
    public bool NamesOtherField => FieldName is { } name && OtherFieldNames.Contains(name, StringComparer.Ordinal);

    #endregion

    #region Actions - Reading

    /// The attribute `attribute` spells. Its field name is its last token
    /// other than `webauthn`; tokens before it it does not recognize are
    /// skipped, as a page that misspells one still means the field.
    public static AutocompleteAttribute Read(string? attribute) {
        var tokens = (attribute ?? "").ToLowerInvariant().Split([' ', '\t', '\n', '\r', '\f'], StringSplitOptions.RemoveEmptyEntries)
            .ToList();
        if (tokens.Count > 0 && tokens[^1] == "webauthn") tokens.RemoveAt(tokens.Count - 1);
        if (tokens.Count == 0 || Unnamed.Contains(tokens[^1], StringComparer.Ordinal)) return new(null, null);
        string fieldName = tokens[^1];
        var leading = tokens.Take(tokens.Count - 1).ToList();
        var scope = leading.Where(token => token.StartsWith(SectionPrefix, StringComparison.Ordinal) && token.Length > SectionPrefix.Length)
            .Take(1).Concat(leading.Where(token => Modes.Contains(token, StringComparer.Ordinal)).Take(1)).ToList();
        return new(scope.Count == 0 ? null : string.Join(' ', scope), Contacts.Contains(fieldName, StringComparer.Ordinal) ? null : fieldName);
    }

    #endregion
}
