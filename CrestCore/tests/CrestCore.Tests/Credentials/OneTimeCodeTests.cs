using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Authenticator codes: reading a setup key or link, making RFC 6238 and
/// Steam codes from it, finding the fields of a form that take one, and
/// spreading a code across them.
public sealed class OneTimeCodeTests {
    /// RFC 6238's seeds for SHA-1, SHA-256 and SHA-512, 20, 32 and 64 bytes of
    /// ASCII digits, in base32.
    private const string Sha1Seed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
    private const string Sha256Seed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA";
    private const string Sha512Seed =
        "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA";

    /// A ten-byte key, the shortest a setup may hold.
    private const string Key = "JBSWY3DPEHPK3PXP";

    private static OneTimeCodeSetup Numeric(string secret, OneTimeCodeAlgorithm algorithm, int digits) =>
        new(secret, "", "", algorithm, digits, 30, OneTimeCodeStyle.Numeric);

    private static OneTimeCodeSetup Read(string text) {
        var parsed = OneTimeCodeSetup.Read(text);
        Assert.Null(parsed.Refusal);
        return Assert.IsType<OneTimeCodeSetup>(parsed.Setup);
    }

    private static CodeSetupRefusal? Refusal(string text) {
        var parsed = OneTimeCodeSetup.Read(text);
        Assert.Null(parsed.Setup);
        return parsed.Refusal;
    }

    private static FormField Field(int index, FormInputType type, string autocomplete = "", string name = "", string label = "",
        int? maxLength = null, string inputMode = "", bool visible = true) =>
        new(index, type, autocomplete, name, "", label, "", visible, false, false, null, maxLength, null, inputMode, []);

    private static IReadOnlyList<int>? CodeFields(IReadOnlyList<FormField> fields, int focused) =>
        OneTimeCodeFields.Understand(fields, focused)?.Fields;

    private static IReadOnlyList<int>? CodeField(FormField field) => CodeFields([field], field.Index);

    private static FormField[] Boxes(int count, FormInputType? type = null, int first = 0) =>
        [.. Enumerable.Range(first, count).Select(index => Field(index, type ?? FormInputType.Text, maxLength: 1))];

    private static Rejection Refused(Func<object?> rule) => Assert.Throws<Rejected>(rule).Rejection;

    #region Codes

    [Theory]
    [InlineData(59, "94287082", "46119246", "90693936")]
    [InlineData(1111111109, "07081804", "68084774", "25091201")]
    [InlineData(1111111111, "14050471", "67062674", "99943326")]
    [InlineData(1234567890, "89005924", "91819424", "93441116")]
    [InlineData(2000000000, "69279037", "90698825", "38618901")]
    [InlineData(20000000000, "65353130", "77737706", "47863826")]
    public void CodesMatchRfc6238(double time, string sha1, string sha256, string sha512) {
        Assert.Equal(sha1, Numeric(Sha1Seed, OneTimeCodeAlgorithm.Sha1, 8).ReadingAt(time).Code);
        Assert.Equal(sha256, Numeric(Sha256Seed, OneTimeCodeAlgorithm.Sha256, 8).ReadingAt(time).Code);
        Assert.Equal(sha512, Numeric(Sha512Seed, OneTimeCodeAlgorithm.Sha512, 8).ReadingAt(time).Code);
    }

    [Fact]
    public void CountersMatchRfc4226() {
        string[] expected = ["755224", "287082", "359152", "969429", "338314", "254676", "287922", "162583", "399871", "520489"];
        var setup = Numeric(Sha1Seed, OneTimeCodeAlgorithm.Sha1, 6);
        for (int counter = 0; counter < expected.Length; counter++) {
            Assert.Equal(expected[counter], setup.CodeFor(counter));
            // A code of time counts periods of 30 seconds since 1970.
            Assert.Equal(new OneTimeCodeReading(expected[counter], counter * 30, counter * 30 + 30), setup.ReadingAt(counter * 30 + 29.5));
        }
    }

    [Fact]
    public void SteamCodesAreFiveCharactersOfItsAlphabet() {
        var setup = Read($"otpauth://totp/Steam:player?secret={Key}&encoder=steam");
        var reading = setup.ReadingAt(1_700_000_000);
        Assert.Equal(5, reading.Code.Length);
        Assert.All(reading.Code, character => Assert.Contains(character, "23456789BCDFGHJKMNPQRTVWXY"));
        Assert.Equal(reading, setup.ReadingAt(1_700_000_000));
        Assert.Equal(new OneTimeCodeReading("2KM2P", 1_699_999_980, 1_700_000_010), reading);
        Assert.Equal("3D7YK", setup.ReadingAt(1_700_000_010).Code);
    }

    [Fact]
    public void ASetupThatMakesNoCodesOrATimeOutOfRangeIsRefused() {
        using var app = new CrestApp();
        var setup = Numeric(Key, OneTimeCodeAlgorithm.Sha1, 6);
        Assert.Equal("324550", app.Query(new OneTimeCode(setup, 1_700_000_000)).Code);
        Assert.Equal(new InvalidCodeSetup(CodeSetupRefusal.InvalidDigits), Refused(() => app.Query(new OneTimeCode(setup with { Digits = 9 }, 0))));
        Assert.Equal(new InvalidCodeSetup(CodeSetupRefusal.InvalidPeriod), Refused(() => app.Query(new OneTimeCode(setup with { Period = 5 }, 0))));
        Assert.Equal(new InvalidCodeSetup(CodeSetupRefusal.InvalidSecret),
            Refused(() => app.Query(new OneTimeCode(setup with { Secret = "jbswy3dpehpk3pxp" }, 0))));
        Assert.Equal(new InvalidCodeSetup(CodeSetupRefusal.UnsupportedAlgorithm),
            Refused(() => app.Query(new OneTimeCode(setup with { Style = OneTimeCodeStyle.Steam, Digits = 5, Algorithm = OneTimeCodeAlgorithm.Sha256 }, 0))));
        foreach (double time in new[] { double.NaN, double.PositiveInfinity, -1, 1e300 })
            Assert.Equal(new InvalidCodeTime(), Refused(() => app.Query(new OneTimeCode(setup, time))));
    }

    #endregion

    #region Setups

    [Fact]
    public void LinksSetUpTimeBasedCodes() {
        Assert.Equal(new OneTimeCodeSetup(Key, "Example Co", "alice@example.com", OneTimeCodeAlgorithm.Sha256, 8, 60, OneTimeCodeStyle.Numeric),
            Read($"otpauth://totp/Example%20Co:alice%40example.com?secret={Key}&algorithm=SHA256&digits=8&period=60"));
        // Without parameters, a code is six digits of SHA-1 every 30 seconds.
        Assert.Equal(new OneTimeCodeSetup(Key, "Example", "alice", OneTimeCodeAlgorithm.Sha1, 6, 30, OneTimeCodeStyle.Numeric),
            Read($"  otpauth://totp/Example:%20alice?secret={Key}\n"));
        // The issuer parameter wins over the label's, and a secret may be spaced, padded or in lowercase.
        var setup = Read("OTPAUTH://TOTP/Old:bob?SECRET=jbsw%20y3dp-ehpk-3pxp%3D%3D&Issuer=New+Name&ALGORITHM=sha-512");
        Assert.Equal((Key, "New Name", "bob", OneTimeCodeAlgorithm.Sha512), (setup.Secret, setup.Issuer, setup.Account, setup.Algorithm));
        var unnamed = Read($"otpauth://totp/carol?secret={Key}");
        Assert.Equal(("", "carol"), (unnamed.Issuer, unnamed.Account));
        Assert.Equal(205, Read($"otpauth://totp/x?secret={new string('A', 205)}").Secret.Length);
    }

    [Fact]
    public void SteamSetupsMakeSteamCodes() {
        var steam = new OneTimeCodeSetup(Key, "Steam", "player", OneTimeCodeAlgorithm.Sha1, 5, 30, OneTimeCodeStyle.Steam);
        // Steam's codes are always 5 characters of SHA-1 every 30 seconds, whatever the link says.
        Assert.Equal(steam, Read($"otpauth://totp/Steam:player?secret={Key}&issuer=Steam&encoder=steam&digits=6&period=60"));
        Assert.Equal(steam, Read($"otpauth://steam/Steam:player?secret={Key}"));
        Assert.Equal(steam with { Account = "" }, Read($"steam://{Key.ToLowerInvariant()}"));
    }

    [Fact]
    public void BareKeysSetUpNumericCodes() {
        var setup = new OneTimeCodeSetup(Key, "", "", OneTimeCodeAlgorithm.Sha1, 6, 30, OneTimeCodeStyle.Numeric);
        Assert.Equal(setup, Read(Key));
        Assert.Equal(setup, Read("jbsw y3dp ehpk 3pxp"));
        Assert.Equal(setup, Read("\t JBSW-Y3DP-EHPK-3PXP==\n"));
        using var app = new CrestApp();
        Assert.Equal(new ParsedCodeSetup(setup, null), app.Query(new ParseCodeSetup(Key)));
    }

    [Fact]
    public void TextThatSetsUpNoCodesIsRefused() {
        Assert.Equal(CodeSetupRefusal.NotASetup, Refusal(""));
        Assert.Equal(CodeSetupRefusal.NotASetup, Refusal("hello, world"));
        Assert.Equal(CodeSetupRefusal.NotASetup, Refusal($"https://example.com/?secret={Key}"));
        Assert.Equal(CodeSetupRefusal.NotASetup, Refusal($"otpauth://other/x?secret={Key}"));
        Assert.Equal(CodeSetupRefusal.NotASetup, Refusal(new string('A', OneTimeCodeSetup.MaximumTextLength + 1)));
        Assert.Equal(CodeSetupRefusal.CounterBased, Refusal($"otpauth://hotp/Example:alice?secret={Key}&counter=0"));
        Assert.Equal(CodeSetupRefusal.UnsupportedAlgorithm, Refusal($"otpauth://totp/x?secret={Key}&algorithm=MD5"));
        Assert.Equal(CodeSetupRefusal.UnsupportedAlgorithm, Refusal($"otpauth://totp/x?secret={Key}&encoder=other"));
        Assert.Equal(CodeSetupRefusal.SecretTooShort, Refusal("otpauth://totp/x?secret=JBSWY3DP"));
        Assert.Equal(CodeSetupRefusal.SecretTooShort, Refusal("JBSWY3DPEHPK3PX"));
        Assert.Equal(CodeSetupRefusal.InvalidSecret, Refusal("otpauth://totp/x?issuer=Example"));
        Assert.Equal(CodeSetupRefusal.InvalidSecret, Refusal("otpauth://totp/x?secret=JBSWY3DPEHPK3PX!"));
        Assert.Equal(CodeSetupRefusal.InvalidSecret, Refusal($"otpauth://totp/x?secret={new string('A', 207)}"));
        Assert.Equal(CodeSetupRefusal.InvalidSecret, Refusal("JBSWY3DP=EHPK3PXP"));
        Assert.Equal(CodeSetupRefusal.InvalidSecret, Refusal("123456 789012 345678"));
        Assert.Equal(CodeSetupRefusal.InvalidDigits, Refusal($"otpauth://totp/x?secret={Key}&digits=9"));
        Assert.Equal(CodeSetupRefusal.InvalidDigits, Refusal($"otpauth://totp/x?secret={Key}&digits=six"));
        Assert.Equal(CodeSetupRefusal.InvalidPeriod, Refusal($"otpauth://totp/x?secret={Key}&period=5"));
        Assert.Equal(CodeSetupRefusal.InvalidPeriod, Refusal($"otpauth://totp/x?secret={Key}&period=301"));
        Assert.Equal(CodeSetupRefusal.InvalidPeriod, Refusal($"otpauth://totp/x?secret={Key}&period=-30"));
    }

    [Fact]
    public void SetupsRoundTripThroughTheirLinks() {
        Assert.Equal($"otpauth://totp/Example%20Co:alice%40example.com?secret={Key}&issuer=Example%20Co&algorithm=SHA1&digits=6&period=30",
            Read($"otpauth://totp/Example%20Co:alice%40example.com?secret={Key}").Link().Link);
        Assert.EndsWith("&algorithm=SHA1&digits=5&period=30&encoder=steam", Read($"steam://{Key}").Link().Link, StringComparison.Ordinal);
        OneTimeCodeSetup[] setups = [
            Read("jbsw y3dp ehpk 3pxp"),
            Read($"steam://{Key}"),
            Read($"otpauth://totp/Steam:player?secret={Key}&encoder=steam"),
            new(Sha512Seed, "Bücher & Co + Partner", "a:b c=d?e#f", OneTimeCodeAlgorithm.Sha512, 8, 60, OneTimeCodeStyle.Numeric),
            new(Key, "Issuer: With Colon", "", OneTimeCodeAlgorithm.Sha256, 7, 10, OneTimeCodeStyle.Numeric),
            new(Key, "", "name:with:colons", OneTimeCodeAlgorithm.Sha1, 6, 300, OneTimeCodeStyle.Numeric)
        ];
        foreach (var setup in setups) Assert.Equal(setup, Read(setup.Link().Link));
        using var app = new CrestApp();
        var link = app.Query(new WriteCodeSetup(setups[0]));
        Assert.Equal(new ParsedCodeSetup(setups[0], null), app.Query(new ParseCodeSetup(link.Link)));
        Assert.Equal(new InvalidCodeSetup(CodeSetupRefusal.InvalidDigits),
            Refused(() => app.Query(new WriteCodeSetup(setups[0] with { Digits = 4 }))));
    }

    #endregion

    #region Fields

    [Fact]
    public void AFieldDeclaredOrCalledACodeTakesOne() {
        Assert.Equal([3], CodeField(Field(3, FormInputType.Text, autocomplete: "one-time-code")));
        foreach (string name in new[] { "otp", "otpCode", "loginOtpInput", "user_otp", "totp", "mfa_code", "2fa", "twoFactorCode",
                     "verificationCode", "authCode" })
            Assert.Equal([0], CodeField(Field(0, FormInputType.Text, name: name)));
        foreach (string label in new[] { "One-time code", "Verification code", "Two-factor authentication", "Authenticator code",
                     "Bestätigungscode", "Sicherheitscode", "Einmalcode", "Verifizierungscode", "Code de vérification",
                     "Code à usage unique", "Código de verificación", "Codice di verifica", "Verificatiecode", "Código de verificação" })
            Assert.Equal([0], CodeField(Field(0, FormInputType.Telephone, label: label)));
        Assert.Null(CodeField(Field(0, FormInputType.Text, name: "footprint")));
        Assert.Null(CodeField(Field(0, FormInputType.Email, autocomplete: "one-time-code")));
        Assert.Null(CodeField(Field(0, FormInputType.Text, autocomplete: "one-time-code", visible: false)));
    }

    [Fact]
    public void AFieldCalledJustCodeTakesOneWithADigitKeypadAndACodesLength() {
        Assert.Equal([0], CodeField(Field(0, FormInputType.Text, name: "code", maxLength: 6, inputMode: "numeric")));
        Assert.Equal([0], CodeField(Field(0, FormInputType.Number, label: "Code", maxLength: 6)));
        Assert.Equal([0], CodeField(Field(0, FormInputType.Telephone, name: "code", maxLength: 10)));
        Assert.Null(CodeField(Field(0, FormInputType.Text, name: "code", maxLength: 6)));
        Assert.Null(CodeField(Field(0, FormInputType.Text, name: "code", inputMode: "numeric")));
        Assert.Null(CodeField(Field(0, FormInputType.Text, name: "code", maxLength: 3, inputMode: "numeric")));
        Assert.Null(CodeField(Field(0, FormInputType.Text, name: "code", maxLength: 11, inputMode: "numeric")));
    }

    [Fact]
    public void AFieldForAnotherCodeOrNumberTakesNone() {
        foreach (string label in new[] { "Coupon code", "Promo code", "Voucher code", "Gutscheincode", "Gift card code", "Postal code",
                     "ZIP code", "Postleitzahl", "Captcha code", "Phone number", "Telefonnummer", "Referral code" })
            Assert.Null(CodeField(Field(0, FormInputType.Text, name: "code", label: label, maxLength: 6, inputMode: "numeric")));
        Assert.Null(CodeField(Field(0, FormInputType.Text, name: "otp", label: "Phone number")));
        Assert.Null(CodeField(Field(0, FormInputType.Telephone, autocomplete: "postal-code", name: "code", maxLength: 6)));
        Assert.Null(CodeField(Field(0, FormInputType.Telephone, autocomplete: "tel-national", name: "otp")));
        // The page's own declaration wins over what it calls the field.
        Assert.Equal([0], CodeField(Field(0, FormInputType.Text, autocomplete: "one-time-code", label: "Promo code")));
    }

    [Fact]
    public void NoFieldOfAPaymentCardsFormTakesACode() {
        FormField[] declared = [Field(0, FormInputType.Text, autocomplete: "cc-number"),
            Field(1, FormInputType.Text, name: "code", label: "Security code", maxLength: 4, inputMode: "numeric")];
        Assert.Null(CodeFields(declared, 1));
        FormField[] called = [Field(0, FormInputType.Text, label: "Card number"),
            Field(1, FormInputType.Telephone, label: "Card verification code", maxLength: 4)];
        Assert.Null(CodeFields(called, 1));
        Assert.Null(CodeField(Field(0, FormInputType.Telephone, name: "cvc", label: "Verification code", maxLength: 4)));
    }

    [Fact]
    public void APasswordFieldTakesACodeOnlyWhenCalledOneAndShort() {
        Assert.Equal([0], CodeField(Field(0, FormInputType.Password, autocomplete: "one-time-code", maxLength: 6)));
        Assert.Equal([0], CodeField(Field(0, FormInputType.Password, name: "otp", maxLength: 10)));
        Assert.Null(CodeField(Field(0, FormInputType.Password, autocomplete: "one-time-code")));
        Assert.Null(CodeField(Field(0, FormInputType.Password, name: "otp", maxLength: 11)));
        Assert.Null(CodeField(Field(0, FormInputType.Password, name: "password", maxLength: 6)));
        Assert.Null(CodeField(Field(0, FormInputType.Password, name: "code", maxLength: 6, inputMode: "numeric")));
        Assert.Null(CodeField(Field(0, FormInputType.Password, autocomplete: "current-password", name: "otp", maxLength: 6)));
    }

    [Fact]
    public void SplitFieldsTakeOneCharacterEach() {
        FormField[] form = [Field(0, FormInputType.Email, autocomplete: "username"), .. Boxes(6, first: 1),
            Field(7, FormInputType.Text, name: "remember")];
        Assert.Equal([1, 2, 3, 4, 5, 6], CodeFields(form, 3));
        Assert.Equal([0, 1, 2, 3], CodeFields(Boxes(4, FormInputType.Telephone), 0));
        Assert.Equal([0, 1, 2, 3, 4, 5, 6, 7], CodeFields(Boxes(8, FormInputType.Number), 7));
        Assert.Equal([0, 1, 2, 3, 4, 5], CodeFields(Boxes(6, FormInputType.Password), 2));
        Assert.Null(CodeFields(Boxes(3), 1));
        Assert.Null(CodeFields(Boxes(9), 1));
        Assert.Null(CodeFields([.. Boxes(6).Select(box => box with { MaxLength = 2 })], 1));
        Assert.Null(CodeFields([.. Boxes(6).Select(box => box with { Index = box.Index * 2 })], 2));
        Assert.Null(CodeFields([.. Boxes(6).Select(box => box.Index == 2 ? box with { IsVisible = false } : box)], 1));
        Assert.Null(CodeFields(Boxes(6), 9));
    }

    [Fact]
    public void CodesSpreadAcrossTheirFields() {
        Assert.Equal([new OneTimeCodeEntry(4, "123456")], new OneTimeCodeFields([4]).Spread("123456").Entries);
        Assert.Equal(["1", "2", "3", "4", "5", "6"], new OneTimeCodeFields([1, 2, 3, 4, 5, 6]).Spread("123456").Entries.Select(entry => entry.Text));
        Assert.Equal([1, 2, 3, 4, 5], new OneTimeCodeFields([1, 2, 3, 4, 5]).Spread("2KM2P").Entries.Select(entry => entry.Field));
        Assert.Equal(new MismatchedCodeLength(6, 5), Refused(() => new OneTimeCodeFields([1, 2, 3, 4, 5, 6]).Spread("12345")));
        Assert.Equal(new MismatchedCodeLength(1, 0), Refused(() => new OneTimeCodeFields([4]).Spread("")));
        using var app = new CrestApp();
        Assert.Equal(["8", "8"], app.Query(new SpreadOneTimeCode(new([0, 1]), "88")).Entries.Select(entry => entry.Text));
    }

    #endregion
}
