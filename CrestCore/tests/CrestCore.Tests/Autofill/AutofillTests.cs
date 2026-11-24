using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Address and card autofill as the core answers every platform: card
/// networks and the Luhn check, how a checkout form divides into sections,
/// what a fill writes into each field, and what a sent form offers to keep.
public sealed partial class AutofillTests {
    #region Variables

    private static readonly StandaloneAnswers Core = new();

    /// An English checkout page: contact and shipping fields, then payment,
    /// then a discount code and the site's search box.
    private static readonly IReadOnlyList<FormField> EnglishCheckout = [
        Field(0, "Email", type: FormInputType.Email, autocomplete: "email"),
        Field(1, "First name", name: "firstName"),
        Field(2, "Last name", name: "lastName"),
        Field(3, "Company (optional)", name: "company"),
        Field(4, "Address", name: "address1"),
        Field(5, "", name: "address2", placeholder: "Apartment, suite, etc. (optional)"),
        Field(6, "City", name: "city"),
        Field(7, "Country/Region", name: "countryCode", type: FormInputType.Select,
            options: [new("", "Select"), new("CA", "Canada"), new("DE", "Germany"), new("US", "United States")]),
        Field(8, "State", name: "provinceCode", type: FormInputType.Select,
            options: [new("", "State"), new("AL", "Alabama"), new("CA", "California"), new("NY", "New York")]),
        Field(9, "ZIP code", name: "postalCode"),
        Field(10, "Phone", name: "phone", type: FormInputType.Telephone),
        Field(11, "Card number", name: "cardnumber", type: FormInputType.Telephone, placeholder: "1234 1234 1234 1234", maxLength: 19),
        Field(12, "Expiration date", name: "exp-date", placeholder: "MM / YY"),
        Field(13, "Security code", name: "cvc", type: FormInputType.Telephone),
        Field(14, "Name on card", name: "ccname"),
        Field(15, "Discount code or gift card", name: "reductions"),
        Field(16, "Search", name: "q")
    ];

    /// A German checkout page without autocomplete attributes, with the house
    /// number apart from the street.
    private static readonly IReadOnlyList<FormField> GermanCheckout = [
        Field(0, "Anrede", name: "salutation", type: FormInputType.Select, options: [new("mr", "Herr"), new("ms", "Frau")]),
        Field(1, "Vorname", name: "firstname"),
        Field(2, "Nachname", name: "lastname"),
        Field(3, "Firma (optional)", name: "company"),
        Field(4, "Straße", name: "street"),
        Field(5, "Hausnummer", name: "housenumber"),
        Field(6, "Adresszusatz", name: "additional"),
        Field(7, "PLZ", name: "zipcode"),
        Field(8, "Ort", name: "city"),
        Field(9, "Bundesland", name: "state", type: FormInputType.Select,
            options: [new("", "Bitte wählen"), new("BY", "Bayern"), new("BE", "Berlin"), new("HH", "Hamburg")]),
        Field(10, "Land", name: "country", type: FormInputType.Select,
            options: [new("", "Bitte wählen"), new("276", "Deutschland"), new("40", "Österreich"), new("756", "Schweiz")]),
        Field(11, "Telefon", name: "phone", type: FormInputType.Telephone),
        Field(12, "E-Mail-Adresse", name: "email", type: FormInputType.Email),
        Field(13, "Geburtsdatum", name: "birthday"),
        Field(14, "Karteninhaber", name: "holder"),
        Field(15, "Kartennummer", name: "pan"),
        Field(16, "Gültig bis", name: "expiry", placeholder: "MM/JJ"),
        Field(17, "Prüfnummer", name: "cvc", maxLength: 4)
    ];

    private static readonly AddressRecord Ada = new(Guid.NewGuid(), "Home", "Ada", "Augusta", "Lovelace", "Analytical Engines",
        ["Hauptstraße 5a", "Hinterhaus"], "Berlin", "Berlin", "10115", "DE", "+49 30 1234567", "ada@example.com");

    private static readonly CardRecord Visa = new(Guid.NewGuid(), "Everyday", "Ada Lovelace", "4242424242424242", 8, 2029, "123", null);

    #endregion

    #region Actions - Helpers

    private static FormField Field(int index, string label, string name = "", FormInputType? type = null, string autocomplete = "",
        string placeholder = "", int? maxLength = null, IReadOnlyList<FormOption>? options = null, bool entered = false) =>
        new(index, type ?? FormInputType.Text, autocomplete, name, "", label, placeholder, true, entered, entered, null, maxLength, null, "",
            options ?? []);

    /// The roles of a section's fields by their index.
    private static Dictionary<int, AutofillFieldRole> Roles(AutofillSection? section) =>
        Assert.IsType<AutofillSection>(section).Fields.ToDictionary(reading => reading.Field, reading => reading.Role);

    /// What a fill from `focused` writes, by field index.
    private static Dictionary<int, string> Filled(AutofillPlan plan) => plan.Values.ToDictionary(value => value.Field, value => value.Value);

    private static Dictionary<int, string> FillAddress(IReadOnlyList<FormField> fields, int focused, AddressRecord? address = null) =>
        Filled(Core.Query(new AddressFill(fields, focused, address ?? Ada)));

    private static Dictionary<int, string> FillCard(IReadOnlyList<FormField> fields, int focused, CardRecord? card = null) =>
        Filled(Core.Query(new CardFill(fields, focused, card ?? Visa)));

    #endregion

    #region Actions - Card Numbers

    /// Each network is known by its longest matching range of leading digits,
    /// and a number is complete only at one of its network's lengths with a
    /// right check digit.
    [Fact]
    public void CardNumbersNameTheirNetworkByTheLongestRangeAndPassLuhn() {
        (string Number, CardNetwork Network)[] cards = [
            ("4242 4242 4242 4242", CardNetwork.Visa), ("5555-5555-5555-4444", CardNetwork.Mastercard),
            ("2223003122003222", CardNetwork.Mastercard), ("378282246310005", CardNetwork.AmericanExpress),
            ("6011111111111117", CardNetwork.Discover), ("6221260000000000", CardNetwork.Discover),
            ("3056930009020004", CardNetwork.DinersClub), ("36227206271667", CardNetwork.DinersClub), ("3530111333300000", CardNetwork.Jcb),
            ("6200000000000005", CardNetwork.UnionPay), ("6759649826438453", CardNetwork.Maestro), ("2200000000000004", CardNetwork.Mir),
            ("9999999999999995", CardNetwork.Unknown)
        ];
        foreach (var (number, network) in cards) {
            var summary = Core.Query(new CardDetails(number));
            Assert.Equal(network, summary.Network);
            Assert.True(summary.IsValid, number);
            Assert.Equal(number[^4..], summary.LastFour);
        }
        Assert.False(Core.Query(new CardDetails("4242424242424241")).IsValid);
        // A Visa number of 15 digits passes Luhn but is not a length Visa issues.
        Assert.False(Core.Query(new CardDetails("424242424242424")).IsValid);
        Assert.Equal(new CardSummary(CardNetwork.Unknown, "", false), Core.Query(new CardDetails("4242 4242 4242 424x")));
        Assert.Equal(new CardSummary(CardNetwork.Unknown, "", false), Core.Query(new CardDetails(new string('4', 20))));
        Assert.Equal([4, 6, 5], CardNetwork.AmericanExpress.Grouping);
        Assert.Equal(4, CardNetwork.AmericanExpress.SecurityCodeLength);
    }

    #endregion
}
