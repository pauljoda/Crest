using System.Text.RegularExpressions;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a field of a sign-in form is for: the autocomplete token that
/// declares it, the words in the page's own names for a field that suggest
/// it, and what focusing it offers. A username field offers what its form's
/// password field does, so clicking either shows the same popup.
internal sealed class FieldRole {
    #region Static Variables

    private const RegexOptions Matching = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;

    public static readonly FieldRole Username = new(token: "username",
        suggestedBy: new(@"user|login|log-in|signin|sign-in|identifier|account|benutzer|anmeldename|utilisateur|identifiant|usuario|utente|gebruiker",
            Matching),
        offerOn: purpose => purpose.UsernameOffer);

    public static readonly FieldRole CurrentPassword = new(token: "current-password",
        suggestedBy: new(@"current|old|existing|aktuell|bisherig|ancien|actuel|anterior|attuale|vecchi|huidig", Matching),
        offerOn: _ => FieldOffer.SavedLogins);

    public static readonly FieldRole NewPassword = new(token: "new-password",
        suggestedBy: new(@"new|neu|nouveau|nouvelle|nuev|nuov|novo|nova|nieuw|create|choose|confirm|retype|re-type|repeat|again|verify|bestätig|wiederhol|répét|repetir|ripet|herhaal",
            Matching),
        offerOn: _ => FieldOffer.NewPassword);

    /// What the page calls a field that takes something other than an account
    /// name, such as a search, a code or a coupon.
    private static readonly Regex NotAnAccount = new(
        @"search|query|^q$|coupon|promo|voucher|gutschein|captcha|otp|one.?time|verification|\bcode\b|suche|recherche|buscar|cerca|zoek",
        Matching);

    /// What the page calls a field that takes an email address or a phone
    /// number, which may name an account.
    private static readonly Regex NamesContact = new(
        @"e-?mail|mail|phone|mobile|\btel\b|courriel|correo|telefon|handy|móvil|cellulare", Matching);

    /// Autocomplete tokens that say a field takes something other than an
    /// account name.
    private static readonly string[] OtherTokens = [
        "one-time-code", "name", "given-name", "family-name", "nickname", "organization", "street-address", "address-line1",
        "address-line2", "address-level1", "address-level2", "postal-code", "country", "country-name", "cc-name", "cc-number",
        "cc-exp", "cc-csc"
    ];

    #endregion

    #region Variables

    /// The autocomplete token that declares the role.
    private readonly string token;

    /// The words that suggest the role in a field's names, label or placeholder.
    private readonly Regex suggestedBy;

    /// What focusing a field of the role offers on a form of a purpose, or
    /// null where it offers nothing.
    private readonly Func<FormPurpose, FieldOffer?> offerOn;

    #endregion

    #region Constructors

    private FieldRole(string token, Regex suggestedBy, Func<FormPurpose, FieldOffer?> offerOn) {
        this.token = token;
        this.suggestedBy = suggestedBy;
        this.offerOn = offerOn;
    }

    #endregion

    #region Actions - Reading

    /// Whether the page declares `field` to have this role.
    public bool Declares(FormField field) => field.Declares(token);

    /// Whether the page's names for `field` suggest this role.
    public bool Suggests(FormField field) => field.IsCalled(suggestedBy);

    /// What focusing a field of this role offers on a form for `purpose`, or
    /// null where it offers nothing.
    public FieldOffer? OfferOn(FormPurpose purpose) => offerOn(purpose);

    /// Whether `field` takes something that is not an account name.
    public static bool TakesOtherThanAccount(FormField field) =>
        OtherTokens.Any(field.Declares) || field.IsCalled(NotAnAccount);

    /// Whether the page calls `field` an email address or a phone number.
    public static bool TakesContact(FormField field) => field.IsCalled(NamesContact);

    #endregion
}
