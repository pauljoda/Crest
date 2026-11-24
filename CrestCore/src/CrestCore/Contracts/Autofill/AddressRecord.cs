using System.Text;

namespace CrestCore.Contracts;

/// An address a Space keeps for filling forms. `Label` is the person's name
/// for it, such as Home. `StreetLines` are its street address, at most
/// `MaximumStreetLines` of them, `City` and `Region` what the standard calls
/// its second and first address levels, and `Country` its ISO 3166-1 alpha-2
/// code, or empty. Every text is at most `MaximumTextLength` characters. The
/// core keeps none: a question that fills or proposes one carries it and
/// forgets it.
[HoldsSecrets]
public sealed record AddressRecord(Guid Id, string Label, string GivenName, string AdditionalName, string FamilyName,
    string Organization, IReadOnlyList<string> StreetLines, string City, string Region, string PostalCode, string Country,
    string Phone, string Email) {
    #region Static Variables

    public const int MaximumStreetLines = 3;

    public const int MaximumTextLength = 200;

    #endregion

    #region Variables

    /// The person's name, its parts joined by spaces.
    internal string FullName => string.Join(' ', new[] { GivenName, AdditionalName, FamilyName }
        .Select(part => part.Trim()).Where(part => part.Length > 0));

    /// The street lines that hold text, trimmed.
    internal IReadOnlyList<string> Lines => [.. StreetLines.Select(line => line.Trim()).Where(line => line.Length > 0)];

    #endregion

    #region Actions - Validation

    /// This record, or `Rejected` with `InvalidAutofillRecord` when a field
    /// breaks its limits.
    internal AddressRecord Validated() {
        string[] texts = [Label, GivenName, AdditionalName, FamilyName, Organization, City, Region, PostalCode, Phone, Email];
        if (texts.Any(text => text.Length > MaximumTextLength) || StreetLines.Count > MaximumStreetLines
            || StreetLines.Any(line => line.Length > MaximumTextLength)
            || Country.Length != 0 && (Country.Length != 2 || !Country.All(char.IsAsciiLetter)))
            throw new Rejected(new InvalidAutofillRecord());
        return this;
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("AddressRecord { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name nothing of the address.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Id = {Id}, Address = <redacted>");
        return true;
    }

    #endregion
}
