namespace CrestCore.Contracts;

/// Why an extension install ended without installing, as its engine or the
/// core found it. A reason travels as its index in `All`, so `All` is
/// append-only.
public sealed class ExtensionInstallFailure {
    #region Static Variables

    /// The Space the install goes into is out of reach: locked, being
    /// deleted, gone, or its profile could not load.
    public static readonly ExtensionInstallFailure SpaceUnavailable = new(name: "space_unavailable",
        message: "The Space is no longer available.", closesReview: true);

    /// The package could not be downloaded, or its source would not serve it.
    public static readonly ExtensionInstallFailure DownloadFailed = new(name: "download_failed",
        message: "Couldn’t download this extension.");

    /// The engine refused the package: it failed verification, or the
    /// engine would not install it.
    public static readonly ExtensionInstallFailure Refused = new(name: "refused",
        message: "This extension couldn’t be verified or installed.");

    /// The person, or the core on their behalf, declined the install or
    /// stopped it.
    public static readonly ExtensionInstallFailure Canceled = new(name: "canceled", message: "Installation canceled.");

    public static IReadOnlyList<ExtensionInstallFailure> All { get; } = [SpaceUnavailable, DownloadFailed, Refused, Canceled];

    #endregion

    #region Variables

    /// The reason's stored spelling.
    public string Name { get; }

    /// What the install's review tells the person.
    [Localized]
    public string Message { get; }

    /// The review of an install that ends this way closes rather than saying
    /// why, since the Space it showed is out of reach.
    public bool ClosesReview { get; }

    #endregion

    #region Constructors

    private ExtensionInstallFailure(string name, string message, bool closesReview = false) {
        Name = name;
        Message = message;
        ClosesReview = closesReview;
    }

    #endregion

    #region Actions - Lookup

    public static ExtensionInstallFailure? Named(string? name) => All.FirstOrDefault(failure => failure.Name == name);

    #endregion
}
