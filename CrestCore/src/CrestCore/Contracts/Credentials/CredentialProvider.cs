namespace CrestCore.Contracts;

/// Where a Space's saved passwords come from. A provider travels as its index
/// in `All`, so `All` is append-only.
public sealed class CredentialProvider {
    #region Static Variables

    /// Crest's own passwords, kept in the Space's Keychain vault.
    public static readonly CredentialProvider CrestPasswords = new(name: "crest-passwords", keepsSpaceVault: true, needsPairing: false);
    /// The person's iCloud Keychain, reached through Apple's password manager helper.
    public static readonly CredentialProvider ApplePasswords = new(name: "apple-passwords", keepsSpaceVault: false, needsPairing: true);

    public static IReadOnlyList<CredentialProvider> All { get; } = [CrestPasswords, ApplePasswords];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether the provider's passwords live in Crest's per-Space Keychain vault.
    public bool KeepsSpaceVault { get; }

    /// Whether the person must pair Crest with the provider before it answers.
    public bool NeedsPairing { get; }

    #endregion

    #region Constructors

    private CredentialProvider(string name, bool keepsSpaceVault, bool needsPairing) {
        Name = name;
        KeepsSpaceVault = keepsSpaceVault;
        NeedsPairing = needsPairing;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialProvider? Named(string? name) => All.FirstOrDefault(provider => provider.Name == name);

    #endregion
}
