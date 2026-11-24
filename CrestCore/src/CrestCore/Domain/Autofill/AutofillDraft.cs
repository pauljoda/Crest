using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a sent form's section said, gathered field by field, from which a
/// capture proposes an address or a card. The parts of a name, a street line
/// and its house number, and a card number split across fields are kept
/// apart until the record is made.
[HoldsSecrets]
internal sealed class AutofillDraft(AutofillSection section) {
    #region Variables

    public AutofillSection Section { get; } = section;

    /// The street lines the section gave, by their place.
    public string?[] StreetLines { get; } = new string?[AddressRecord.MaximumStreetLines];

    /// The digits of the card number, from each of its fields in turn.
    public StringBuilder CardDigits { get; } = new();

    public string FullName { get; set; } = "";

    public string GivenName { get; set; } = "";

    public string AdditionalName { get; set; } = "";

    public string FamilyName { get; set; } = "";

    public string Organization { get; set; } = "";

    public string HouseNumber { get; set; } = "";

    public string City { get; set; } = "";

    public string Region { get; set; } = "";

    public string PostalCode { get; set; } = "";

    public string Country { get; set; } = "";

    public string Phone { get; set; } = "";

    public string Email { get; set; } = "";

    public string Cardholder { get; set; } = "";

    public string CardholderGivenName { get; set; } = "";

    public string CardholderFamilyName { get; set; } = "";

    public int? ExpiryMonth { get; set; }

    public int? ExpiryYear { get; set; }

    #endregion

    #region Actions - Reading

    /// Whether the section holds a field of `role`.
    public bool Has(AutofillFieldRole role) => Section.Has(role);

    #endregion

    #region Actions - Proposing

    /// The address the section gave: one with a street line and a postal
    /// code or a city, or null. A name given in parts wins over one given
    /// whole, and a house number joins the first street line after the
    /// street.
    public AddressRecord? Address() {
        var lines = StreetLines.OfType<string>().Select(line => line.Trim()).Where(line => line.Length > 0).ToList();
        if (lines.Count == 0 || PostalCode.Length == 0 && City.Length == 0) return null;
        if (HouseNumber.Length > 0) lines[0] = StreetLine.Joined(lines[0], HouseNumber);
        if (lines[0].Length > AddressRecord.MaximumTextLength) return null;
        var name = GivenName.Length > 0 || AdditionalName.Length > 0 || FamilyName.Length > 0
            ? new PersonName(GivenName, AdditionalName, FamilyName) : PersonName.Split(FullName);
        return new(Guid.Empty, "", name.Given, name.Additional, name.Family, Organization, lines, City, Region, PostalCode, Country,
            Phone, Email);
    }

    /// The card the section gave: one whose number is complete and whose
    /// expiry is a month of a four-digit year, or null. The security code is
    /// never kept from a sent form.
    public CardRecord? Card() {
        if (CardNumber.Read(CardDigits.ToString()) is not { IsValid: true } number || ExpiryMonth is not int month
            || ExpiryYear is not int year || month is < 1 or > 12 || year is < 1000 or > 9999)
            return null;
        string cardholder = Cardholder.Length > 0 ? Cardholder
            : string.Join(' ', new[] { CardholderGivenName, CardholderFamilyName }.Where(part => part.Length > 0));
        return new(Guid.Empty, "", cardholder.Length > CardRecord.MaximumTextLength ? "" : cardholder, number.Digits, month, year, null,
            null);
    }

    #endregion

    #region Actions - Text

    public override string ToString() => $"AutofillDraft {{ Kind = {Section.Kind.Name}, Values = <redacted> }}";

    #endregion
}
