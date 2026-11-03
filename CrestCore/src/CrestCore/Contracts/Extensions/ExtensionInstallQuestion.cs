namespace CrestCore.Contracts;

/// Whether to install the extension package the engine verified: its
/// `Name`, `Version` and `Summary`, the `Permissions` it asks for, as the
/// engine words them, and its icon as PNG bytes. `CanWithholdSiteAccess` says
/// the person may keep its site access back, and `WithholdsSiteAccess` says
/// installing does so unless they choose otherwise.
public sealed record ExtensionInstallQuestion(string ExtensionId, string Name, string Version, string Summary,
    IReadOnlyList<string> Permissions, byte[]? Icon, bool CanWithholdSiteAccess, bool WithholdsSiteAccess) : PromptQuestion {
    #region Actions - Consent

    /// Whether the person's consent to `approved` answers this question too:
    /// the same verified package, at the same version, asking for the same
    /// access.
    internal bool IsCoveredBy(ExtensionInstallQuestion approved) =>
        ExtensionId == approved.ExtensionId && Version == approved.Version
        && Permissions.Order(StringComparer.Ordinal).SequenceEqual(approved.Permissions.Order(StringComparer.Ordinal), StringComparer.Ordinal);

    #endregion
}
