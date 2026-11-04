namespace CrestCore.Contracts;

#region Models

/// What the person can change about an installed extension.
public enum ExtensionChange {
    Enable,
    Disable,
    Remove,
    Pin,
    Unpin
}

/// One extension an engine installed in a profile: what it is, whether it is
/// enabled, whether the person may change it, which an extension a policy
/// installed is not, the permission warnings it carries as the engine words
/// them, whether it came from the Chrome Web Store, and its options page, if
/// it has one. Its icon stays with the engine (`ExtensionIcons`).
public sealed record InstalledExtension(string Id, string Name, string Version, string Description, bool Enabled,
    bool Changeable, IReadOnlyList<string> Permissions, bool FromWebStore, string? OptionsUrl);

/// An extension install as the core runs it: the Space it installs in first,
/// the engine and extension, where it stands, how many Spaces it installed
/// in, and why it failed, if it did.
public sealed record ExtensionInstallState(Guid InstallId, Guid SpaceId, EngineKind Engine, string ExtensionId,
    ExtensionInstallStage Stage, int InstalledCount, ExtensionInstallFailure? Failure);

/// The Spaces a copy of an extension may go to, one for each profile, and
/// whether the engine has listed every profile a copy could go to, so that
/// none of those left out may still turn out to have the extension.
public sealed record ExtensionCopyDestinationList(IReadOnlyList<Guid> SpaceIds, bool Listed);

#endregion

#region Changes

/// The extensions `Engine` installed in the profile `ProfileId` names, as it
/// listed them now. The core publishes them only while no locked Space
/// browses with the profile.
public sealed record InstalledExtensionsChanged(EngineKind Engine, Guid ProfileId, IReadOnlyList<InstalledExtension> Extensions)
    : Change;

/// An extension install moved on.
public sealed record ExtensionInstallChanged(ExtensionInstallState Install) : Change;

/// Whether to install the extension install `InstallId` verified waits on the
/// person.
public sealed record ExtensionInstallAsked(Guid PromptId, Guid InstallId, ExtensionInstallQuestion Question) : Change;

#endregion

#region Rejections

/// The Space is a private window's, which runs no extension a person
/// installed, so its extensions cannot be listed, changed or installed.
public sealed record SpaceIsPrivate(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Extensions can’t be changed in a private window.";

    #endregion
}

/// The engine listed no such extension in the Space's profile.
public sealed record UnknownExtension(string ExtensionId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That extension is no longer installed.";

    #endregion
}

/// The person may not change the extension, as one a policy installed.
public sealed record ExtensionNotChangeable(string ExtensionId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This extension is managed for you and can’t be changed.";

    #endregion
}

#endregion
