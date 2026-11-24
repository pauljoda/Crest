namespace CrestCore.Contracts;

/// An input's `type` as a credential form reads it. A type the page names
/// that is not listed here, such as `search` or `checkbox`, reads as `Other`.
/// A member travels as its index in `All`, so `All` is append-only.
public sealed class FormInputType {
    #region Static Variables

    public static readonly FormInputType Text = new(name: "text", namesAccount: true);
    public static readonly FormInputType Email = new(name: "email", namesAccount: true, namesEmail: true);
    public static readonly FormInputType Telephone = new(name: "tel", namesAccount: true);
    public static readonly FormInputType Password = new(name: "password", holdsPassword: true);
    public static readonly FormInputType Hidden = new(name: "hidden");
    public static readonly FormInputType Other = new(name: "other");

    public static IReadOnlyList<FormInputType> All { get; } = [Text, Email, Telephone, Password, Hidden, Other];

    #endregion

    #region Variables

    /// The type as the page spells it, in lowercase.
    public string Name { get; }

    /// Whether a field of this type may hold the account's name: a username,
    /// an email address or a phone number.
    internal bool NamesAccount { get; }

    /// Whether the field takes an email address.
    internal bool NamesEmail { get; }

    /// Whether the field takes a password.
    internal bool HoldsPassword { get; }

    #endregion

    #region Constructors

    private FormInputType(string name, bool namesAccount = false, bool namesEmail = false, bool holdsPassword = false) {
        Name = name;
        NamesAccount = namesAccount;
        NamesEmail = namesEmail;
        HoldsPassword = holdsPassword;
    }

    #endregion
}
