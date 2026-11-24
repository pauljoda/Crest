using CrestCore.Domain;

namespace CrestCore.Contracts;

/// How the core reads a form for signing in: what it is for, and which of its
/// fields, by `FormField.Index`, holds the account's name, its current
/// password and each new password, the first of them the new one and any
/// after it confirming it. `KeptPassword` is the field whose password sending
/// the form keeps, if any.
public sealed record SignInForm(FormPurpose Purpose, int? Username, int? CurrentPassword, IReadOnlyList<int> NewPasswords,
    int? KeptPassword) {
    #region Static Variables

    /// The most password fields one form may show and still be read.
    private const int MaximumPasswordFields = 3;

    /// A form the core does not read as one for signing in.
    internal static SignInForm Quiet { get; } = new(FormPurpose.None, null, null, [], null);

    #endregion

    #region Variables

    /// The first new password field, the one a save keeps, if any.
    internal int? NewPassword => NewPasswords.Count > 0 ? NewPasswords[0] : null;

    #endregion

    #region Actions - Reading

    /// The reading of `fields`, listed in the order the page shows them. Only
    /// visible password fields count; an account name may come from a hidden
    /// field the page declares to hold one, as a change-password form does.
    internal static SignInForm Understand(IReadOnlyList<FormField> fields) {
        ArgumentNullException.ThrowIfNull(fields);
        var passwords = fields.Where(field => field.InputType.HoldsPassword && field.IsVisible).ToList();
        if (passwords.Count > MaximumPasswordFields) return Quiet;
        var (current, news) = PasswordRoles(passwords);
        if (passwords.Count > 0 && current is null && news.Count == 0) return Quiet;
        var (username, isDeclared) = UsernameField(fields, passwords.FirstOrDefault());
        var purpose = FormPurpose.For(hasUsername: username is not null, usernameIsClear: isDeclared,
            hasCurrentPassword: current is not null, hasNewPassword: news.Count > 0);
        var form = new SignInForm(purpose, username?.Index, current?.Index, [.. news.Select(field => field.Index)], null);
        return form with { KeptPassword = purpose.KeptPassword(form) };
    }

    /// The role of the field at `index` in this form, or null when it has none.
    internal FieldRole? RoleOf(int index) {
        if (index == Username) return FieldRole.Username;
        if (index == CurrentPassword) return FieldRole.CurrentPassword;
        return NewPasswords.Contains(index) ? FieldRole.NewPassword : null;
    }

    /// The field at `index` among `fields`, or null.
    internal static FormField? FieldAt(IReadOnlyList<FormField> fields, int? index) =>
        index is int wanted ? fields.FirstOrDefault(field => field.Index == wanted) : null;

    /// Which visible password fields take the current password and which take
    /// a new one. One field is current unless the page says it is new; two
    /// are a current and a new one when one of them reads as current, and
    /// otherwise a new one and its confirmation; three are current, new and
    /// confirmation. A field the page declares current wins over one whose
    /// names only suggest it. Two fields both declared current read as neither.
    private static (FormField? Current, List<FormField> News) PasswordRoles(List<FormField> passwords) {
        if (passwords.Count == 0) return (null, []);
        if (passwords.Count == 1)
            return ReadsAsNew(passwords[0]) ? (null, [passwords[0]]) : (passwords[0], []);
        if (passwords.Count(FieldRole.CurrentPassword.Declares) > 1) return (null, []);
        var current = passwords.FirstOrDefault(FieldRole.CurrentPassword.Declares) ?? passwords.FirstOrDefault(ReadsAsCurrent);
        if (passwords.Count == MaximumPasswordFields)
            current ??= passwords.FirstOrDefault(field => !FieldRole.NewPassword.Declares(field));
        return (current, [.. passwords.Where(field => field != current)]);
    }

    private static bool ReadsAsNew(FormField field) =>
        FieldRole.NewPassword.Declares(field)
        || !FieldRole.CurrentPassword.Declares(field) && FieldRole.NewPassword.Suggests(field) && !FieldRole.CurrentPassword.Suggests(field);

    private static bool ReadsAsCurrent(FormField field) =>
        FieldRole.CurrentPassword.Declares(field)
        || !FieldRole.NewPassword.Declares(field) && FieldRole.CurrentPassword.Suggests(field);

    /// The field holding the account's name, and whether the page makes that
    /// clear: it declares the field a username, or calls it one. Otherwise
    /// the field is the email field, or the account-name field nearest before
    /// the first password, or on a form without one, its only such field when
    /// the page calls it an email address or phone number, so a lone chat or
    /// comment box is never taken for one.
    private static (FormField? Field, bool IsClear) UsernameField(IReadOnlyList<FormField> fields, FormField? firstPassword) {
        // A field the page declares a username is one, whatever its names say.
        if (fields.Where(field => !field.InputType.HoldsPassword && FieldRole.Username.Declares(field))
                .OrderByDescending(field => field.IsVisible).FirstOrDefault() is { } declared)
            return (declared, true);
        var candidates = fields.Where(field => !field.InputType.HoldsPassword && !FieldRole.TakesOtherThanAccount(field)).ToList();
        var visible = candidates
            .Where(field => field.IsVisible && field.InputType.NamesAccount
                && (firstPassword is null || field.Index < firstPassword.Index))
            .ToList();
        if (visible.LastOrDefault(FieldRole.Username.Suggests) is { } called) return (called, true);
        if (visible.FirstOrDefault(field => field.Declares("email") || field.InputType.NamesEmail) is { } email) return (email, false);
        if (firstPassword is not null) return (visible.LastOrDefault(), false);
        return (visible.Count == 1 && FieldRole.TakesContact(visible[0]) ? visible[0] : null, false);
    }

    #endregion
}
