using System.Text.RegularExpressions;

namespace CrestCore.Contracts;

/// The fields of a form that take a one-time code, by `FormField.Index`: one
/// field that takes the whole code, or the split fields that take one
/// character each, in order.
public sealed record OneTimeCodeFields(IReadOnlyList<int> Fields) {
    #region Static Variables

    private const RegexOptions Matching = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;

    /// The autocomplete token that declares a field takes a one-time code.
    private const string CodeToken = "one-time-code";

    /// The `inputmode` that asks for a keypad of digits.
    private const string NumericInputMode = "numeric";

    /// How many split fields a code may be spread across.
    private const int FewestSplitFields = 4;
    private const int MostSplitFields = 8;

    /// The fewest characters a field that takes a whole code may hold.
    private const int ShortestCode = 4;

    /// The most characters a field called just "code" may hold.
    private const int LongestPlainCode = 10;

    /// The most characters a password field that takes a code may hold.
    private const int LongestPasswordCode = 10;

    /// What the page calls a field that takes a one-time code. A short word
    /// such as `otp` counts at the start or end of a word, or capitalized
    /// inside one, so `loginOtpInput` counts and `footprint` doesn't.
    private static readonly Regex CalledCode = new(
        @"(?<![a-z])(otp|mfa)|(otp|mfa)(?![a-z])|(?-i:Otp|Mfa)|2fa|totp|(?<![a-z])one.?time|two.?factor|verification.?code"
        + @"|verify.?code|authenticator|auth.?code|authentication.?code|best(ä|ae|a)tigungs?.?code|sicherheits.?code|einmal.?code"
        + @"|verifizierungs.?code|code.?de.?v[ée]rification|code.?[àa].?usage.?unique|c[óo]digo.?de.?verificaci[óo]n"
        + @"|codice.?di.?verifica|verificatie.?code|c[óo]digo.?de.?verifica[çc][ãa]o",
        Matching);

    /// A field the page calls just "code".
    private static readonly Regex CalledJustCode = new(@"^\W*code\W*$", Matching);

    /// What the page calls a field that takes some other code or number: a
    /// coupon, promotion, voucher or gift card, a postal code, a captcha or a
    /// phone number.
    private static readonly Regex CalledOther = new(
        @"coupon|promo|voucher|gutschein|rabatt|discount|referral|invit|gift|geschenk|cadeau|regalo|postal|post.?code|zip"
        + @"|(?<![a-z])plz(?![a-z])|postleitzahl|captcha|phone.?(num|no(?![a-z]))|telephone.?num|mobile.?num|telefonnummer"
        + @"|handynummer|telefoonnummer|num[ée]ro.?de.?t[ée]l[ée]phone|n[úu]mero.?de.?tel[ée]fon[eo]|numero.?di.?telefono",
        Matching);

    /// What the page calls a field of a payment card: its number, holder or
    /// security code.
    private static readonly Regex CalledCard = new(
        @"card.?(num|no(?![a-z])|security|verification|code|holder)|cc.?num|credit.?card|kreditkarte|kartennummer|kartenprüf"
        + @"|num[ée]ro.?de.?carte|n[úu]mero.?de.?tarjeta|tarjeta.?de.?cr[ée]dito|numero.?di.?carta|kaartnummer"
        + @"|n[úu]mero.?do.?cart[ãa]o|cvc|cvv|cvn|(?<![a-z])csc|cryptogramme",
        Matching);

    /// Autocomplete tokens that say a field takes something other than a
    /// one-time code.
    private static readonly string[] OtherTokens = [
        "username", "email", "current-password", "new-password", "postal-code", "tel", "tel-country-code", "tel-national",
        "tel-area-code", "tel-local", "tel-local-prefix", "tel-local-suffix", "tel-extension"
    ];

    /// Autocomplete tokens of a payment card's fields.
    private static readonly string[] CardTokens = [
        "cc-name", "cc-given-name", "cc-additional-name", "cc-family-name", "cc-number", "cc-exp", "cc-exp-month", "cc-exp-year",
        "cc-csc", "cc-type"
    ];

    #endregion

    #region Actions - Reading

    /// The fields of `fields`, listed in the order the page shows them, that
    /// take a one-time code with the field at `focused`, or null when that
    /// field takes none. A run of 4 to 8 visible fields of consecutive indices
    /// that each hold one character is split fields. Otherwise the field takes
    /// a whole code when the page declares it does, or calls it one, or calls
    /// it just "code" and gives it a keypad of digits and a length of 4 to 10.
    /// A password field takes one only when the page declares or calls it one
    /// and limits it to 10 characters. A field the page calls a coupon, postal
    /// code, captcha or phone number takes none unless it declares a code, and
    /// no field of a payment card's form takes one.
    internal static OneTimeCodeFields? Understand(IReadOnlyList<FormField> fields, int focused) {
        ArgumentNullException.ThrowIfNull(fields);
        if (SignInForm.FieldAt(fields, focused) is not { } field || fields.Any(IsOfCard)) return null;
        var split = SplitAround(fields, field);
        if (split.Count is >= FewestSplitFields and <= MostSplitFields) return new([.. split.Select(box => box.Index)]);
        return TakesCode(field) ? new([field.Index]) : null;
    }

    /// The run of split fields with consecutive indices that `focused` is
    /// one of, in order, or none when it isn't one.
    private static List<FormField> SplitAround(IReadOnlyList<FormField> fields, FormField focused) {
        if (!IsSplitField(focused)) return [];
        var byIndex = fields.DistinctBy(field => field.Index).ToDictionary(field => field.Index);
        int first = focused.Index;
        int last = focused.Index;
        while (byIndex.TryGetValue(first - 1, out var before) && IsSplitField(before)) first--;
        while (byIndex.TryGetValue(last + 1, out var after) && IsSplitField(after)) last++;
        return [.. Enumerable.Range(first, last - first + 1).Select(index => byIndex[index])];
    }

    /// Whether `field` could take one character of a split code.
    private static bool IsSplitField(FormField field) =>
        field.IsVisible && field.InputType.TakesCode && field.MaxLength == 1 && !TakesOther(field);

    /// Whether `field` takes a whole one-time code.
    private static bool TakesCode(FormField field) {
        if (!field.IsVisible || !field.InputType.TakesCode || field.MaxLength < ShortestCode) return false;
        bool declared = field.Declares(CodeToken);
        if (!declared && TakesOther(field)) return false;
        bool called = declared || field.IsCalled(CalledCode);
        if (field.InputType.HoldsPassword) return called && field.MaxLength <= LongestPasswordCode;
        return called || (field.IsCalled(CalledJustCode) && field.MaxLength <= LongestPlainCode
            && (field.InputType.KeysDigits || string.Equals(field.InputMode, NumericInputMode, StringComparison.OrdinalIgnoreCase)));
    }

    /// Whether the page says `field` takes something other than a one-time code.
    private static bool TakesOther(FormField field) => OtherTokens.Any(field.Declares) || field.IsCalled(CalledOther);

    /// Whether `field` belongs to a payment card.
    private static bool IsOfCard(FormField field) => CardTokens.Any(field.Declares) || field.IsCalled(CalledCard);

    #endregion

    #region Actions - Entering

    /// What to enter in each field to enter `code`: the whole code in one
    /// field, or one character in each split field, refused when the code's
    /// length doesn't fit.
    internal OneTimeCodeFill Spread(string code) {
        ArgumentNullException.ThrowIfNull(code);
        if (Fields.Count == 1 && code.Length > 0) return new([new(Fields[0], code)]);
        if (Fields.Count > 1 && code.Length == Fields.Count)
            return new([.. Fields.Select((field, place) => new OneTimeCodeEntry(field, code[place..(place + 1)]))]);
        throw new Rejected(new MismatchedCodeLength(Fields.Count, code.Length));
    }

    #endregion
}
