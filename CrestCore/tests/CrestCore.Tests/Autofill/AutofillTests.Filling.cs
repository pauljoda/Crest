using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class AutofillTests {
    #region Actions - Filling

    /// A fill writes only into the section of the focused field: an address
    /// never into the card fields beside it, nor a card into the address, and
    /// a select takes the value of the option that names the record's value.
    [Fact]
    public void AFillWritesOnlyTheFocusedSection() {
        var grace = new AddressRecord(Guid.NewGuid(), "Work", "Grace", "", "Hopper", "", ["1 Infinite Loop", "Suite 100"], "Cupertino",
            "California", "95014", "US", "+1 408 555 0100", "grace@example.com");
        Assert.Equal(new Dictionary<int, string> {
            [0] = "grace@example.com",
            [1] = "Grace",
            [2] = "Hopper",
            [4] = "1 Infinite Loop",
            [5] = "Suite 100",
            [6] = "Cupertino",
            [7] = "US",
            [8] = "CA",
            [9] = "95014",
            [10] = "+1 408 555 0100"
        }, FillAddress(EnglishCheckout, 6, grace));
        Assert.Equal(new Dictionary<int, string> {
            [11] = "4242 4242 4242 4242",
            [12] = "08 / 29",
            [13] = "123",
            [14] = "Ada Lovelace"
        }, FillCard(EnglishCheckout, 12));
        Assert.Empty(FillAddress(EnglishCheckout, 12));
        Assert.Empty(FillCard(EnglishCheckout, 6));
        Assert.Empty(FillAddress(EnglishCheckout, 15));
    }

    /// A German checkout takes the street apart from its house number, its
    /// regions and countries by their German names, and a card's expiry as
    /// its placeholder shows it. A card that keeps no security code leaves
    /// that field alone.
    [Fact]
    public void AGermanCheckoutTakesTheStreetApartFromTheHouseNumber() {
        Assert.Equal(new Dictionary<int, string> {
            [1] = "Ada",
            [2] = "Lovelace",
            [3] = "Analytical Engines",
            [4] = "Hauptstraße",
            [5] = "5a",
            [6] = "Hinterhaus",
            [7] = "10115",
            [8] = "Berlin",
            [9] = "BE",
            [10] = "276",
            [11] = "+49 30 1234567",
            [12] = "ada@example.com"
        }, FillAddress(GermanCheckout, 4));
        Assert.Equal(new Dictionary<int, string> {
            [14] = "Ada Lovelace",
            [15] = "4242424242424242",
            [16] = "08/29",
            [17] = "123"
        }, FillCard(GermanCheckout, 15));
        Assert.False(FillCard(GermanCheckout, 15, Visa with { SecurityCode = null }).ContainsKey(17));
    }

    /// Selects match a value by an option's value or text, ignoring case and
    /// diacritics: countries by code or by name in the languages Crest reads,
    /// regions by name or code, and months and years in every spelling. An
    /// option whose text holds the value as whole words is taken when it is
    /// the only one, and a select with no option for the value is left alone.
    [Fact]
    public void SelectsChooseTheOptionThatNamesTheValue() {
        string? Country(AddressRecord address, params FormOption[] options) =>
            FillAddress([Field(0, "Street"), Field(1, "City"), Field(2, "ZIP"), Field(3, "Country", type: FormInputType.Select, options: options)],
                0, address).GetValueOrDefault(3);
        string? Region(AddressRecord address, params FormOption[] options) =>
            FillAddress([Field(0, "Street"), Field(1, "City"), Field(2, "State", type: FormInputType.Select, options: options)], 0, address)
                .GetValueOrDefault(2);
        Assert.Equal("DEU", Country(Ada, new("", "Choose"), new("AUT", "Austria"), new("DEU", "Germany")));
        Assert.Equal("1", Country(Ada, new("2", "Autriche"), new("1", "Allemagne")));
        Assert.Equal("x", Country(Ada, new FormOption("x", "🇩🇪 DEUTSCHLAND")));
        Assert.Equal("at", Country(Ada with { Country = "AT" }, new("de", "Deutschland"), new("at", "Osterreich")));
        Assert.Null(Country(Ada, new("a", "Austria"), new("b", "Australia")));

        var newYork = Ada with { Region = "NY", Country = "US" };
        Assert.Equal("ny", Region(newYork, new("ca", "California"), new("ny", "New York")));
        Assert.Equal("2", Region(newYork with { Region = "California" }, new("1", "AL - Alabama"), new("2", "CA - California")));
        Assert.Equal("BY", Region(Ada with { Region = "Bavaria" }, new("BE", "Berlin"), new("BY", "Bayern")));
        Assert.Equal("Québec", Region(Ada with { Region = "QC", Country = "CA" }, new("Ontario", "Ontario"), new("Québec", "Québec")));

        Dictionary<int, string> Expiry(FormOption[] months, FormOption[] years) => FillCard([
            Field(0, "Card number"), Field(1, "Expiry", type: FormInputType.Select, options: months),
            Field(2, "Expiry", type: FormInputType.Select, options: years)
        ], 0);
        FormOption[] Months(Func<int, FormOption> option) => [new("", "Monat"), .. Enumerable.Range(1, 12).Select(option)];
        string[] french = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];
        var fourDigits = Enumerable.Range(2026, 8).Select(year => new FormOption($"{year}", $"{year}")).ToArray();
        var twoDigits = Enumerable.Range(26, 8).Select(year => new FormOption($"{year}", $"20{year}")).ToArray();
        Assert.Equal(new Dictionary<int, string> { [0] = "4242424242424242", [1] = "08", [2] = "2029" },
            Expiry(Months(month => new($"{month:00}", $"{month:00}")), fourDigits));
        Assert.Equal("m8", Expiry(Months(month => new($"m{month}", french[month - 1])), fourDigits)[1]);
        Assert.Equal("x8", Expiry(Months(month => new($"x{month}", $"{month:00} - {french[month - 1]}")), fourDigits)[1]);
        Assert.Equal("29", Expiry(Months(month => new($"{month}", $"{month}")), twoDigits)[2]);
        Assert.False(Expiry(Months(month => new($"{month}", $"{month}")), fourDigits[..3]).ContainsKey(2));
    }

    /// A card's expiry takes the format its field shows, or else the one its
    /// length suggests; a month field takes the year and month. Its number is
    /// grouped as its network groups it where the placeholder shows groups
    /// and the field holds them, and split across consecutive fields.
    [Fact]
    public void ExpiryAndNumberTakeTheShapeOfTheirField() {
        string Expiry(FormField field) => FillCard([Field(0, "Card number"), field], 0)[1];
        Assert.Equal("0829", Expiry(Field(1, "Expiry", maxLength: 4)));
        Assert.Equal("08/29", Expiry(Field(1, "Expiry", maxLength: 5)));
        Assert.Equal("08/2029", Expiry(Field(1, "Expiry", maxLength: 7)));
        Assert.Equal("08/2029", Expiry(Field(1, "Expiry", placeholder: "MM/YYYY")));
        Assert.Equal("0829", Expiry(Field(1, "Expiry", placeholder: "MMYY")));
        Assert.Equal("08/29", Expiry(Field(1, "Date d'expiration (MM/AA)")));
        Assert.Equal("2029-08", Expiry(Field(1, "Expiration", type: FormInputType.Month)));
        Assert.Equal("29", Expiry(Field(1, "Year", placeholder: "YY")));
        Assert.Equal("2029", Expiry(Field(1, "Jahr")));
        Assert.Equal("08", Expiry(Field(1, "Month")));

        var amex = Visa with { Number = "378282246310005" };
        string Number(FormField field, CardRecord? card = null) => FillCard([field, Field(1, "CVC")], 0, card)[0];
        Assert.Equal("3782 822463 10005", Number(Field(0, "Card number", placeholder: "0000 0000 0000 0000", maxLength: 19), amex));
        Assert.Equal("4242-4242-4242-4242", Number(Field(0, "Card number", placeholder: "XXXX-XXXX-XXXX-XXXX")));
        Assert.Equal("4242424242424242", Number(Field(0, "Card number", placeholder: "1234 1234 1234 1234", maxLength: 16)));
        FormField[] split = [.. Enumerable.Range(0, 4).Select(part => Field(part, "", name: $"cardnumber{part + 1}", maxLength: 4))];
        Assert.Equal(new Dictionary<int, string> { [0] = "4242", [1] = "4242", [2] = "4242", [3] = "4242" },
            FillCard(split, 2, Visa with { Number = "4242424242424242" }));
    }

    /// Names and streets take the shape of their fields: a whole name or its
    /// parts, a German "Name" after the Vorname as the family name, a street
    /// on lines of a text area or joined in one line, a middle initial where
    /// one letter fits, and a country's name or its code where only that fits.
    [Fact]
    public void NamesAndStreetsTakeTheShapeOfTheirFields() {
        FormField[] whole = [
            Field(0, "Full name"), Field(1, "Street address", type: FormInputType.TextArea), Field(2, "City"),
            Field(3, "Country", maxLength: 2), Field(4, "Middle initial", maxLength: 1)
        ];
        Assert.Equal(new Dictionary<int, string> {
            [0] = "Ada Augusta Lovelace",
            [1] = "Hauptstraße 5a\nHinterhaus",
            [2] = "Berlin",
            [3] = "DE",
            [4] = "A"
        }, FillAddress(whole, 0));
        FormField[] oneLine = [Field(0, "Vorname"), Field(1, "Name"), Field(2, "Adresse"), Field(3, "Land")];
        Assert.Equal(new Dictionary<int, string> {
            [0] = "Ada",
            [1] = "Lovelace",
            [2] = "Hauptstraße 5a, Hinterhaus",
            [3] = "Germany"
        }, FillAddress(oneLine, 0));
        Assert.Equal("Hauptstraße 5a, Hinterhaus",
            FillAddress([Field(0, "", autocomplete: "street-address"), Field(1, "City"), Field(2, "ZIP")], 0)[0]);
    }

    #endregion
}
