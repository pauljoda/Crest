namespace CrestCore.Contracts;

/// An input's `type` as a form reads it, or `select` and `textarea` for those
/// elements. A type the page names that is not listed here, such as `search`
/// or `checkbox`, reads as `Other`.
/// A member travels as its index in `All`, so `All` is append-only.
public sealed class FormInputType {
    #region Static Variables

    public static readonly FormInputType Text = new(name: "text", namesAccount: true, takesCode: true, takesAutofill: true);
    public static readonly FormInputType Email = new(name: "email", namesAccount: true, namesEmail: true, takesAutofill: true);
    public static readonly FormInputType Telephone = new(name: "tel", namesAccount: true, takesCode: true, keysDigits: true,
        takesAutofill: true);
    public static readonly FormInputType Password = new(name: "password", holdsPassword: true, takesCode: true);
    public static readonly FormInputType Hidden = new(name: "hidden");
    public static readonly FormInputType Other = new(name: "other");
    public static readonly FormInputType Number = new(name: "number", takesCode: true, keysDigits: true, takesAutofill: true);
    public static readonly FormInputType Select = new(name: "select", takesAutofill: true, offersChoices: true);
    public static readonly FormInputType TextArea = new(name: "textarea", takesAutofill: true, spansLines: true);
    public static readonly FormInputType Month = new(name: "month", takesAutofill: true, takesMonth: true);

    public static IReadOnlyList<FormInputType> All { get; } = [Text, Email, Telephone, Password, Hidden, Other, Number, Select, TextArea, Month];

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

    /// Whether a field of this type may take a one-time code, whole or one
    /// character of it.
    internal bool TakesCode { get; }

    /// Whether the field is typed on a keypad of digits.
    internal bool KeysDigits { get; }

    /// Whether address and card autofill may write into the field: one that
    /// takes text, a number, a choice or a month.
    internal bool TakesAutofill { get; }

    /// Whether the field is a select, whose value is one of its options.
    internal bool OffersChoices { get; }

    /// Whether the field takes several lines of text.
    internal bool SpansLines { get; }

    /// Whether the field takes a month, spelled as its year and month.
    internal bool TakesMonth { get; }

    #endregion

    #region Constructors

    private FormInputType(string name, bool namesAccount = false, bool namesEmail = false, bool holdsPassword = false,
        bool takesCode = false, bool keysDigits = false, bool takesAutofill = false, bool offersChoices = false,
        bool spansLines = false, bool takesMonth = false) {
        Name = name;
        NamesAccount = namesAccount;
        NamesEmail = namesEmail;
        HoldsPassword = holdsPassword;
        TakesCode = takesCode;
        KeysDigits = keysDigits;
        TakesAutofill = takesAutofill;
        OffersChoices = offersChoices;
        SpansLines = spansLines;
        TakesMonth = takesMonth;
    }

    #endregion
}
