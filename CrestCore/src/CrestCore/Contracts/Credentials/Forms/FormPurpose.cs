using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What a form is for, as far as signing in goes, what its username field
/// offers, and what sending it does: a step that names the account is
/// remembered for the step after it, and a form with a password the person
/// entered becomes a candidate to save. A member travels as its index in
/// `All`, so `All` is append-only.
public sealed class FormPurpose {
    #region Static Variables

    public static readonly FormPurpose None = new(name: "none");

    /// A step that asks only for the account's name, and says so. With no
    /// password field to go by, it offers logins only once some are saved.
    public static readonly FormPurpose UsernameStep = new(name: "usernameStep", usernameOffer: FieldOffer.SavedLoginsWhenSome,
        remembersUsername: true);

    /// A form that asks only for something that may be the account's name,
    /// such as an email address. Sending it is remembered, but it offers no
    /// logins, since it is as likely a newsletter as a sign-in.
    public static readonly FormPurpose PossibleUsernameStep = new(name: "possibleUsernameStep", remembersUsername: true);

    public static readonly FormPurpose SignIn = new(name: "signIn", usernameOffer: FieldOffer.SavedLogins,
        keptPassword: form => form.CurrentPassword);

    /// A form that makes an account. Its username field offers the new
    /// password its password fields do.
    public static readonly FormPurpose SignUp = new(name: "signUp", usernameOffer: FieldOffer.NewPassword,
        keptPassword: form => form.NewPassword);

    /// A form that takes the current password and a new one. Without an
    /// account name, the saved login whose password is the current one names it.
    public static readonly FormPurpose ChangePassword = new(name: "changePassword", usernameOffer: FieldOffer.SavedLogins,
        keptPassword: form => form.NewPassword, findsAccountByCurrentPassword: true);

    public static IReadOnlyList<FormPurpose> All { get; } = [None, UsernameStep, PossibleUsernameStep, SignIn, SignUp, ChangePassword];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the form's username field offers, or null where it offers nothing.
    internal FieldOffer? UsernameOffer { get; }

    /// Whether sending the form remembers its username for the next step.
    internal bool RemembersUsername { get; }

    /// Whether, without an account name, the current password finds the account.
    internal bool FindsAccountByCurrentPassword { get; }

    /// The field whose password sending the form keeps, if any.
    private readonly Func<SignInForm, int?> keptPassword;

    #endregion

    #region Constructors

    private FormPurpose(string name, FieldOffer? usernameOffer = null, bool remembersUsername = false,
        Func<SignInForm, int?>? keptPassword = null, bool findsAccountByCurrentPassword = false) {
        Name = name;
        UsernameOffer = usernameOffer;
        RemembersUsername = remembersUsername;
        FindsAccountByCurrentPassword = findsAccountByCurrentPassword;
        this.keptPassword = keptPassword ?? (_ => null);
    }

    #endregion

    #region Actions - Reading

    /// The purpose of a form with these fields. `usernameIsClear` says the page
    /// declares or calls its account-name field a username.
    internal static FormPurpose For(bool hasUsername, bool usernameIsClear, bool hasCurrentPassword, bool hasNewPassword) {
        if (hasCurrentPassword) return hasNewPassword ? ChangePassword : SignIn;
        if (hasNewPassword) return SignUp;
        if (!hasUsername) return None;
        return usernameIsClear ? UsernameStep : PossibleUsernameStep;
    }

    /// The field of `form` whose password sending it keeps, if any.
    internal int? KeptPassword(SignInForm form) => keptPassword(form);

    #endregion
}
