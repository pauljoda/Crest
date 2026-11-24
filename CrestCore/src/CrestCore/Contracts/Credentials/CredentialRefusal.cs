namespace CrestCore.Contracts;

/// Why a Space's passwords do not serve a use (see `CredentialAccess`). A
/// refusal travels as its index in `All`, so `All` is append-only.
public sealed class CredentialRefusal {
    #region Static Variables

    /// The window is private, and keeps nothing.
    public static readonly CredentialRefusal PrivateBrowsing = new(name: "privateBrowsing");
    /// The Space's password manager is off.
    public static readonly CredentialRefusal ManagerOff = new(name: "managerOff");
    /// The page has no HTTPS.
    public static readonly CredentialRefusal InsecureOrigin = new(name: "insecureOrigin");

    public static IReadOnlyList<CredentialRefusal> All { get; } = [PrivateBrowsing, ManagerOff, InsecureOrigin];

    #endregion

    #region Variables

    public string Name { get; }

    #endregion

    #region Constructors

    private CredentialRefusal(string name) {
        Name = name;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialRefusal? Named(string? name) => All.FirstOrDefault(refusal => refusal.Name == name);

    #endregion
}
