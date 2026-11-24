using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class AutofillTests {
    #region Actions - Capture

    /// What the German checkout sends, as the person typed it.
    private static readonly IReadOnlyList<AutofillValue> GermanValues = [
        new(0, "ms"), new(1, "Ada"), new(2, "Lovelace"), new(4, "Hauptstraße"), new(5, "5a"), new(6, "Hinterhaus"), new(7, "10115"),
        new(8, "Berlin"), new(9, "BE"), new(10, "276"), new(11, "+49 30 1234567"), new(12, "ada@example.com"), new(13, "10.12.1815"),
        new(14, "Ada Lovelace"), new(15, "4242 4242 4242 4242"), new(16, "08/29"), new(17, "123")
    ];

    private static IReadOnlyList<FormField> Entered(IReadOnlyList<FormField> fields) =>
        [.. fields.Select(field => field with { HasValue = true, EnteredByPerson = true })];

    /// A sent German checkout proposes the address with the house number
    /// back on its street, its region as the option read and its country as
    /// a code, and the card with its expiry but never its security code.
    [Fact]
    public void ASentCheckoutProposesItsAddressAndCard() {
        var proposal = Core.Query(new AutofillCapture(Entered(GermanCheckout), GermanValues));
        var address = Assert.IsType<AddressRecord>(proposal.Address);
        Assert.Equal(new AddressRecord(Guid.Empty, "", "Ada", "", "Lovelace", "", address.StreetLines, "Berlin", "Berlin", "10115", "DE",
            "+49 30 1234567", "ada@example.com"), address);
        Assert.Equal(["Hauptstraße 5a", "Hinterhaus"], address.StreetLines);
        Assert.Equal(new CardRecord(Guid.Empty, "", "Ada Lovelace", "4242424242424242", 8, 2029, null, null), proposal.Card);

        var english = Core.Query(new AutofillCapture(Entered(EnglishCheckout), [
            new(1, "Grace"), new(2, "Hopper"), new(4, "1 Infinite Loop"), new(6, "Cupertino"), new(7, "US"), new(8, "CA"), new(9, "95014"),
            new(11, "5555 5555 5555 4444"), new(12, "12 / 2030"), new(15, "SAVE10")
        ]));
        Assert.Equal(("California", "US"), (english.Address?.Region, english.Address?.Country));
        Assert.Equal((12, 2030, "5555555555554444"), (english.Card?.ExpiryMonth, english.Card?.ExpiryYear, english.Card?.Number));

        FormField[] whole = [Field(0, "Full name", entered: true), Field(1, "Address", entered: true), Field(2, "Postcode", entered: true)];
        var named = Core.Query(new AutofillCapture(whole, [new(0, "Ada Augusta Lovelace"), new(1, "1 Main Street"), new(2, "SW1A 1AA")]));
        Assert.Equal(("Ada", "Augusta", "Lovelace"), (named.Address?.GivenName, named.Address?.AdditionalName, named.Address?.FamilyName));
    }

    /// A form whose values the person did not enter offers nothing to keep,
    /// nor does an address without a street and a postal code or city, or a
    /// card whose number fails its check or whose expiry is not a month.
    [Fact]
    public void AnIncompleteOrUnenteredFormProposesNothing() {
        Assert.Equal(new AutofillProposal(null, null), Core.Query(new AutofillCapture(GermanCheckout, GermanValues)));
        var partial = GermanValues.Where(value => value.Field is not (7 or 8)).Select(value => value.Field == 15 ? value with { Value = "4242 4242 4242 4241" } : value);
        Assert.Equal(new AutofillProposal(null, null), Core.Query(new AutofillCapture(Entered(GermanCheckout), [.. partial])));
        var expired = GermanValues.Select(value => value.Field == 16 ? value with { Value = "13/29" } : value).ToList();
        Assert.Null(Core.Query(new AutofillCapture(Entered(GermanCheckout), expired)).Card);
    }

    #endregion
}
