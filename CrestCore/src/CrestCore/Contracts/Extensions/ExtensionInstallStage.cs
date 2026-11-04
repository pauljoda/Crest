namespace CrestCore.Contracts;

/// Where an extension install stands, and what its review shows for it. A
/// stage travels as its index in `All`, so `All` is append-only.
public sealed class ExtensionInstallStage {
    #region Static Variables

    /// The first Space's profile downloads the package, and the engine
    /// verifies it before it asks whether to install it.
    public static readonly ExtensionInstallStage Downloading = new(name: "downloading", isPreparing: true);

    /// The engine asked whether to install the package it verified, and the
    /// question waits on the person.
    public static readonly ExtensionInstallStage Asking = new(name: "asking");

    /// The install was accepted and goes into its Spaces, one at a time.
    public static readonly ExtensionInstallStage Installing = new(name: "installing", isInstalling: true);

    /// The install is done.
    public static readonly ExtensionInstallStage Installed = new(name: "installed", hasEnded: true, hasInstalled: true);

    /// The install ended without installing in its first Space: its failure
    /// says why.
    public static readonly ExtensionInstallStage Failed = new(name: "failed", hasEnded: true);

    public static IReadOnlyList<ExtensionInstallStage> All { get; } = [Downloading, Asking, Installing, Installed, Failed];

    #endregion

    #region Variables

    /// The stage's stored spelling.
    public string Name { get; }

    /// The install prepares its package, and has nothing to ask yet.
    public bool IsPreparing { get; }

    /// The install was accepted and is still going into its Spaces.
    public bool IsInstalling { get; }

    /// The install ended, however it ended.
    public bool HasEnded { get; }

    /// The install ended having done what it set out to.
    public bool HasInstalled { get; }

    #endregion

    #region Constructors

    private ExtensionInstallStage(string name, bool isPreparing = false, bool isInstalling = false, bool hasEnded = false,
        bool hasInstalled = false) {
        Name = name;
        IsPreparing = isPreparing;
        IsInstalling = isInstalling;
        HasEnded = hasEnded;
        HasInstalled = hasInstalled;
    }

    #endregion

    #region Actions - Lookup

    public static ExtensionInstallStage? Named(string? name) => All.FirstOrDefault(stage => stage.Name == name);

    #endregion
}
