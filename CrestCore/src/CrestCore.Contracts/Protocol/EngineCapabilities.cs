namespace CrestCore.Contracts;

/// Capabilities required to register a browsing engine.
public static class EngineCapabilities {
    #region Variables

    public const string Pages = "pages";
    public const string Navigation = "navigation";
    public const string WorkspaceProfiles = "workspace-profiles";
    public const string ProfileDeletion = "profile-deletion";

    /// A Space is one profile, and deleting a Space must erase that profile, so an
    /// engine without either cannot host a browser session at all.
    public static readonly IReadOnlyList<string> Required = [Pages, Navigation, WorkspaceProfiles, ProfileDeletion];

    #endregion
}
