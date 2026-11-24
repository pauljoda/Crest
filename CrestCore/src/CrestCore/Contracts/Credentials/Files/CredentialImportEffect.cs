namespace CrestCore.Contracts;

/// What importing one candidate password does to the Space's saved
/// passwords. An effect travels as its index in `All`, so `All` is
/// append-only.
public sealed class CredentialImportEffect {
    #region Static Variables

    /// No password is saved for the account: the candidate is added.
    public static readonly CredentialImportEffect Adds = new(name: "adds", changesPasswords: true, keepsSavedPassword: false);
    /// The account's saved password differs: the candidate replaces it.
    public static readonly CredentialImportEffect Replaces = new(name: "replaces", changesPasswords: true, keepsSavedPassword: false);
    /// The account's saved password is the candidate's, with the note and
    /// one-time code link the candidate brings, if any: nothing changes.
    public static readonly CredentialImportEffect Matches = new(name: "matches", changesPasswords: false, keepsSavedPassword: true);
    /// The account's saved password is the candidate's, and the candidate
    /// brings a note or one-time code link the saved password lacks or spells
    /// otherwise: the saved password takes them.
    public static readonly CredentialImportEffect UpdatesDetails = new(name: "updatesDetails", changesPasswords: true,
        keepsSavedPassword: true);

    public static IReadOnlyList<CredentialImportEffect> All { get; } = [Adds, Replaces, Matches, UpdatesDetails];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether importing the candidate changes the saved passwords, which an
    /// import counts as accepted.
    public bool ChangesPasswords { get; }

    /// Whether the account keeps the password it has saved, so importing the
    /// candidate asks the person nothing.
    internal bool KeepsSavedPassword { get; }

    #endregion

    #region Constructors

    private CredentialImportEffect(string name, bool changesPasswords, bool keepsSavedPassword) {
        Name = name;
        ChangesPasswords = changesPasswords;
        KeepsSavedPassword = keepsSavedPassword;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialImportEffect? Named(string? name) => All.FirstOrDefault(effect => effect.Name == name);

    #endregion

    #region Actions - Planning

    /// What importing `row` does to the account whose saved password is
    /// `existing`, or to an account with none when it is null.
    internal static CredentialImportEffect Of(ImportedCredential row, ExistingCredential? existing) {
        ArgumentNullException.ThrowIfNull(row);
        if (existing is null) return Adds;
        if (existing.Password != row.Password) return Replaces;
        bool bringsDetails = row.Note is not null && row.Note != existing.Note
            || row.OneTimeCodeLink is not null && row.OneTimeCodeLink != existing.OneTimeCodeLink;
        return bringsDetails ? UpdatesDetails : Matches;
    }

    #endregion
}
