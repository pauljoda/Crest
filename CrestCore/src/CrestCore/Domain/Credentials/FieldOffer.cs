using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What focusing a field of a sign-in form offers: the site's saved logins,
/// which a field of a form that signs in offers even before any are saved, the
/// saved logins of a step that names the account, which show only once some
/// are saved, or a new password.
internal sealed class FieldOffer {
    #region Static Variables

    public static readonly FieldOffer SavedLogins = new(kind: CredentialPasswordKind.Current, quietWithoutLogins: false);

    public static readonly FieldOffer SavedLoginsWhenSome = new(kind: CredentialPasswordKind.Current, quietWithoutLogins: true);

    public static readonly FieldOffer NewPassword = new(kind: CredentialPasswordKind.New, quietWithoutLogins: false);

    #endregion

    #region Variables

    /// Whether the offer fills a saved login or a new password.
    public CredentialPasswordKind Kind { get; }

    /// Whether the offer shows only when the Space has logins for the site.
    public bool QuietWithoutLogins { get; }

    #endregion

    #region Constructors

    private FieldOffer(CredentialPasswordKind kind, bool quietWithoutLogins) {
        Kind = kind;
        QuietWithoutLogins = quietWithoutLogins;
    }

    #endregion
}
