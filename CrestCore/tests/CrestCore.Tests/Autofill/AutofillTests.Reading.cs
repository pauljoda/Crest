using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class AutofillTests {
    #region Actions - Reading

    /// An English checkout reads as an address section and a card section,
    /// each field by its autocomplete token, its type or its names; a card
    /// number in a telephone field is still a card number, and a discount
    /// code or search box is in neither.
    [Fact]
    public void AnEnglishCheckoutReadsAsAnAddressAndACardSection() {
        var address = Core.Query(new AutofillSectionAt(EnglishCheckout, 6)).Section;
        Assert.Equal(AutofillSectionKind.Address, address?.Kind);
        Assert.Equal(new Dictionary<int, AutofillFieldRole> {
            [0] = AutofillFieldRole.Email,
            [1] = AutofillFieldRole.GivenName,
            [2] = AutofillFieldRole.FamilyName,
            [3] = AutofillFieldRole.Organization,
            [4] = AutofillFieldRole.AddressLine1,
            [5] = AutofillFieldRole.AddressLine2,
            [6] = AutofillFieldRole.City,
            [7] = AutofillFieldRole.Country,
            [8] = AutofillFieldRole.Region,
            [9] = AutofillFieldRole.PostalCode,
            [10] = AutofillFieldRole.Phone
        }, Roles(address));
        Assert.Equal([0], address!.Fields.Where(reading => reading.IsDeclared).Select(reading => reading.Field));

        var card = Core.Query(new AutofillSectionAt(EnglishCheckout, 12)).Section;
        Assert.Equal(AutofillSectionKind.Card, card?.Kind);
        Assert.Equal(new Dictionary<int, AutofillFieldRole> {
            [11] = AutofillFieldRole.CardNumber,
            [12] = AutofillFieldRole.Expiry,
            [13] = AutofillFieldRole.SecurityCode,
            [14] = AutofillFieldRole.CardholderName
        }, Roles(card));
        Assert.Null(Core.Query(new AutofillSectionAt(EnglishCheckout, 15)).Section);
        Assert.Null(Core.Query(new AutofillSectionAt(EnglishCheckout, 16)).Section);
    }

    /// A German checkout without autocomplete attributes reads by its German
    /// labels, with the house number apart from the street, and leaves out
    /// the salutation and the birthday.
    [Fact]
    public void AGermanCheckoutReadsByItsLabels() {
        Assert.Equal(new Dictionary<int, AutofillFieldRole> {
            [1] = AutofillFieldRole.GivenName,
            [2] = AutofillFieldRole.FamilyName,
            [3] = AutofillFieldRole.Organization,
            [4] = AutofillFieldRole.AddressLine1,
            [5] = AutofillFieldRole.HouseNumber,
            [6] = AutofillFieldRole.AddressLine2,
            [7] = AutofillFieldRole.PostalCode,
            [8] = AutofillFieldRole.City,
            [9] = AutofillFieldRole.Region,
            [10] = AutofillFieldRole.Country,
            [11] = AutofillFieldRole.Phone,
            [12] = AutofillFieldRole.Email
        }, Roles(Core.Query(new AutofillSectionAt(GermanCheckout, 4)).Section));
        Assert.Equal(new Dictionary<int, AutofillFieldRole> {
            [14] = AutofillFieldRole.CardholderName,
            [15] = AutofillFieldRole.CardNumber,
            [16] = AutofillFieldRole.Expiry,
            [17] = AutofillFieldRole.SecurityCode
        }, Roles(Core.Query(new AutofillSectionAt(GermanCheckout, 16)).Section));

        // One field for the street and its number is the first street line.
        FormField[] combined = [Field(0, "Straße und Hausnummer"), Field(1, "PLZ"), Field(2, "Ort")];
        Assert.Equal(AutofillFieldRole.AddressLine1, Roles(Core.Query(new AutofillSectionAt(combined, 0)).Section)[0]);
    }

    /// Declared shipping and billing addresses are two sections, and so are
    /// two undeclared addresses one after the other; a fill reads only the
    /// one that holds the focused field. Unrecognized tokens such as `off`
    /// leave a field to its names, and a field declared to hold something
    /// else is no part of any section.
    [Fact]
    public void ShippingAndBillingAddressesAreSeparateSections() {
        FormField[] declared = [
            Field(0, "", autocomplete: "shipping given-name"), Field(1, "", autocomplete: "shipping family-name"),
            Field(2, "", autocomplete: "shipping street-address"), Field(3, "", autocomplete: "shipping postal-code"),
            Field(4, "City", autocomplete: "off"),
            Field(5, "", autocomplete: "billing given-name"), Field(6, "", autocomplete: "billing family-name"),
            Field(7, "", autocomplete: "billing street-address"), Field(8, "", autocomplete: "billing postal-code"),
            Field(9, "Birthday", autocomplete: "bday"), Field(10, "", autocomplete: "billing address-level2")
        ];
        Assert.Equal([0, 1, 2, 3, 4], Roles(Core.Query(new AutofillSectionAt(declared, 4)).Section).Keys.Order());
        Assert.Equal([5, 6, 7, 8, 10], Roles(Core.Query(new AutofillSectionAt(declared, 8)).Section).Keys.Order());
        Assert.Null(Core.Query(new AutofillSectionAt(declared, 9)).Section);

        FormField[] repeated = [
            Field(0, "First name"), Field(1, "Last name"), Field(2, "Address"), Field(3, "City"), Field(4, "ZIP"),
            Field(5, "First name"), Field(6, "Last name"), Field(7, "Address"), Field(8, "City"), Field(9, "ZIP")
        ];
        Assert.Equal([5, 6, 7, 8, 9], Roles(Core.Query(new AutofillSectionAt(repeated, 8)).Section).Keys.Order());
    }

    /// A sign-in form, a newsletter box or a lone name is not an address, and
    /// a card field without a card number is a card section only where the
    /// page declares it, as a card form split across frames does.
    [Fact]
    public void FormsWithoutEnoughToFillAreNotSections() {
        FormField[] signIn = [Field(0, "Email", type: FormInputType.Email), Field(1, "Password", type: FormInputType.Password)];
        FormField[] newsletter = [Field(0, "Name"), Field(1, "Email", type: FormInputType.Email)];
        FormField[] account = [Field(0, "Username", autocomplete: "username"), Field(1, "Name"), Field(2, "City"), Field(3, "ZIP")];
        Assert.Null(Core.Query(new AutofillSectionAt(signIn, 0)).Section);
        Assert.Null(Core.Query(new AutofillSectionAt(newsletter, 1)).Section);
        Assert.Null(Core.Query(new AutofillSectionAt(account, 0)).Section);
        Assert.NotNull(Core.Query(new AutofillSectionAt(account, 1)).Section);
        Assert.Null(Core.Query(new AutofillSectionAt([Field(0, "Expiry", placeholder: "MM/YY")], 0)).Section);
        Assert.Equal(AutofillSectionKind.Card,
            Core.Query(new AutofillSectionAt([Field(0, "", autocomplete: "cc-exp", placeholder: "MM/YY")], 0)).Section?.Kind);
        Assert.Null(Core.Query(new AutofillSectionAt([.. EnglishCheckout.Take(11).Select(field => field with { IsVisible = false })], 6))
            .Section);
    }

    #endregion
}
