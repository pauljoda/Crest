namespace CrestCore.Contracts;

/// What a Space's passwords are wanted for, and which of its rules that use is
/// held to (see `CredentialAccess`). A use travels as its index in `All`, so
/// `All` is append-only.
public sealed class CredentialUse {
    #region Static Variables

    /// Listing or reading what the Space's group keeps, as Settings does.
    public static readonly CredentialUse Read = new(name: "read", needsManager: false, refusedInPrivate: false);
    /// Offering or filling a password on a page.
    public static readonly CredentialUse Fill = new(name: "fill", needsManager: true, refusedInPrivate: false);
    /// Saving a password a page submitted or the person entered.
    public static readonly CredentialUse Save = new(name: "save", needsManager: true, refusedInPrivate: true);
    /// Asking whether to save a password a page submitted, which a site the
    /// person asked never to save for doesn't do.
    public static readonly CredentialUse OfferSave = new(name: "offerSave", needsManager: true, refusedInPrivate: true,
        offersSave: true);

    public static IReadOnlyList<CredentialUse> All { get; } = [Read, Fill, Save, OfferSave];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether the use needs the Space's password manager on, and a page it
    /// serves to have HTTPS.
    public bool NeedsManager { get; }

    /// Whether a private window, which keeps nothing, refuses the use.
    public bool RefusedInPrivate { get; }

    /// Whether the use asks the person to save, which the Space's never-save
    /// sites refuse.
    internal bool OffersSave { get; }

    #endregion

    #region Constructors

    private CredentialUse(string name, bool needsManager, bool refusedInPrivate, bool offersSave = false) {
        Name = name;
        NeedsManager = needsManager;
        RefusedInPrivate = refusedInPrivate;
        OffersSave = offersSave;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialUse? Named(string? name) => All.FirstOrDefault(use => use.Name == name);

    #endregion
}
