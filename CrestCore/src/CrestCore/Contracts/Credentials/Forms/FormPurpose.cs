namespace CrestCore.Contracts;

/// What a form is for, as far as signing in goes, and what sending it does: a
/// step that names the account is remembered for the step after it, and a
/// form with a password the person entered becomes a candidate to save. A
/// member travels as its index in `All`, so `All` is append-only.
public sealed class FormPurpose {
    #region Static Variables

    public static readonly FormPurpose None = new(name: "none");

    /// A step that asks only for the account's name, and says so.
    public static readonly FormPurpose UsernameStep = new(name: "usernameStep", offersLogins: true, remembersUsername: true);

    /// A form that asks only for something that may be the account's name,
    /// such as an email address. Sending it is remembered, but it offers no
    /// logins, since it is as likely a newsletter as a sign-in.
    public static readonly FormPurpose PossibleUsernameStep = new(name: "possibleUsernameStep", remembersUsername: true);

    public static readonly FormPurpose SignIn = new(name: "signIn", offersLogins: true,
        keptPassword: form => form.CurrentPassword);

    public static readonly FormPurpose SignUp = new(name: "signUp", keptPassword: form => form.NewPassword);

    /// A form that takes the current password and a new one. Without an
    /// account name, the saved login whose password is the current one names it.
    public static readonly FormPurpose ChangePassword = new(name: "changePassword",
        keptPassword: form => form.NewPassword, findsAccountByCurrentPassword: true);

    public static IReadOnlyList<FormPurpose> All { get; } = [None, UsernameStep, PossibleUsernameStep, SignIn, SignUp, ChangePassword];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether the form's username field offers the site's saved logins.
    internal bool OffersLogins { get; }

    /// Whether sending the form remembers its username for the next step.
    internal bool RemembersUsername { get; }

    /// Whether, without an account name, the current password finds the account.
    internal bool FindsAccountByCurrentPassword { get; }

    /// The field whose password sending the form keeps, if any.
    private readonly Func<SignInForm, int?> keptPassword;

    #endregion

    #region Constructors

    private FormPurpose(string name, bool offersLogins = false, bool remembersUsername = false,
        Func<SignInForm, int?>? keptPassword = null, bool findsAccountByCurrentPassword = false) {
        Name = name;
        OffersLogins = offersLogins;
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
