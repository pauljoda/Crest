namespace CrestCore.Contracts;

/// Why a download looks dangerous. Each reason decides from the platform's
/// facts whether it applies, and whether it holds even for a download the
/// person started. A download the person did not start is always confirmed.
///
/// An assessment lists its reasons in `All` order, and a reason travels as its
/// index there, so `All` is append-only.
public sealed class DownloadRiskReason {
    #region Variables

    public static readonly DownloadRiskReason ExecutableOrInstaller = new(name: "executableOrInstaller",
        applies: facts => facts.RunsCode, confirmsUserInitiated: asksBeforeSavingInstallers => asksBeforeSavingInstallers,
        message: "This file type can install or run software.");
    public static readonly DownloadRiskReason DeceptiveFilename = new(name: "deceptiveFilename",
        applies: facts => facts.HasDeceptiveFilename, confirmsUserInitiated: _ => true,
        message: "The original filename used invisible or direction-changing characters that can disguise its real extension.");
    public static readonly DownloadRiskReason DangerousTypeMismatch = new(name: "dangerousTypeMismatch",
        applies: facts => facts.RunsCode && facts.TypesDisagree, confirmsUserInitiated: _ => true,
        message: "The server-reported file type does not match the filename and one of those types can run software.");

    public static IReadOnlyList<DownloadRiskReason> All { get; } = [ExecutableOrInstaller, DeceptiveFilename, DangerousTypeMismatch];

    private readonly Func<DownloadRiskFacts, bool> applies;

    /// Whether the person must confirm a download with this reason that they
    /// started, given whether they chose to be asked before saving apps and
    /// installers. An installer they started is asked about only when they
    /// chose that; otherwise it follows the platform's quarantine and
    /// Gatekeeper flow. A disguised filename or a type mismatch that runs code
    /// stays suspicious however the download began.
    private readonly Func<bool, bool> confirmsUserInitiated;

    public string Name { get; }

    /// Why the download looks dangerous, as the confirmation tells the person.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private DownloadRiskReason(string name, Func<DownloadRiskFacts, bool> applies, Func<bool, bool> confirmsUserInitiated,
        string message) {
        Name = name;
        this.applies = applies;
        this.confirmsUserInitiated = confirmsUserInitiated;
        Message = message;
    }

    #endregion

    #region Actions - Risk

    public bool Applies(DownloadRiskFacts facts) {
        ArgumentNullException.ThrowIfNull(facts);
        return applies(facts);
    }

    /// Whether the person must confirm a download with this reason, by how it
    /// began and whether they chose to be asked before saving apps and
    /// installers.
    public bool RequiresConfirmation(bool isUserInitiated, bool asksBeforeSavingInstallers) =>
        !isUserInitiated || confirmsUserInitiated(asksBeforeSavingInstallers);

    #endregion

    #region Actions - Lookup

    public static DownloadRiskReason? Named(string? name) => All.FirstOrDefault(reason => reason.Name == name);

    #endregion
}
