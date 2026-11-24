namespace CrestCore.Contracts;

/// What a `PasswordHealth` question finds wrong with a saved password, with
/// what the person is told. A concern travels as its index in `All`, so `All`
/// is append-only.
public sealed class PasswordConcern {
    #region Static Variables

    /// Another saved password has the same password.
    public static readonly PasswordConcern Reused = new(name: "reused", title: "Reused",
        message: "This password is also used for other accounts.", applies: (_, sharing) => sharing.Count > 0);
    /// The password is easy to guess (see `CheckedCredential.HasWeakPassword`).
    public static readonly PasswordConcern Weak = new(name: "weak", title: "Weak", message: "This password is easy to guess.",
        applies: (credential, _) => credential.HasWeakPassword);
    /// The password is saved for a site served over plain HTTP from another
    /// device, so it crosses the network unencrypted.
    public static readonly PasswordConcern InsecureSite = new(name: "insecureSite", title: "No HTTPS",
        message: "This website doesn’t use an encrypted connection.", applies: (credential, _) => !credential.Origin.IsSecure);

    public static IReadOnlyList<PasswordConcern> All { get; } = [Reused, Weak, InsecureSite];

    #endregion

    #region Variables

    public string Name { get; }

    /// What a list of passwords calls the concern, in a word or two.
    [Localized]
    public string Title { get; }

    /// What the person is told.
    [Localized]
    public string Message { get; }

    /// Whether the concern applies to a saved password whose password the
    /// passwords of the given identities share.
    private readonly Func<CheckedCredential, IReadOnlyList<Guid>, bool> applies;

    #endregion

    #region Constructors

    private PasswordConcern(string name, string title, string message, Func<CheckedCredential, IReadOnlyList<Guid>, bool> applies) {
        Name = name;
        Title = title;
        Message = message;
        this.applies = applies;
    }

    #endregion

    #region Actions - Lookup

    public static PasswordConcern? Named(string? name) => All.FirstOrDefault(concern => concern.Name == name);

    #endregion

    #region Actions - Checking

    /// The concerns that apply to `credential`, whose password the saved
    /// passwords `sharing` names share, in the order of `All`.
    internal static IReadOnlyList<PasswordConcern> Of(CheckedCredential credential, IReadOnlyList<Guid> sharing) =>
        [.. All.Where(concern => concern.applies(credential, sharing))];

    #endregion
}
