namespace CrestCore.Contracts;

/// <summary>Whether a Space offers to save and fill passwords, and where it keeps them.</summary>
public sealed record CredentialPreferences(bool IsEnabled, bool SyncsCrestPasswordsWithICloud, bool AlsoOffersSaveToSystemPasswords);
