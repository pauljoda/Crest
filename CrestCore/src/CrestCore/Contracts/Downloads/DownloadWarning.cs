namespace CrestCore.Contracts;

/// What a download's engine warned about, as Crest reads it: what the person
/// is told when it asks them to keep the file, why the download failed when
/// the engine blocked it, and the core's risk reasons that already name it.
/// An engine reports an `EngineDownloadWarning`, whose spelling the engine
/// contract fixes, and `Of` reads it as the warning it stands for.
///
/// A warning travels as its index in `All`, so `All` is append-only.
public sealed class DownloadWarning {
    #region Static Variables

    public static readonly DownloadWarning InsecureConnection = new(name: "insecureConnection",
        engineWarning: EngineDownloadWarning.InsecureConnection, confirms: true,
        approvalMessage: "This file was transferred over an insecure connection and could have been changed by someone else. "
            + "Keep it only if you trust its source.",
        failure: DownloadFailure.BlockedInsecure);
    public static readonly DownloadWarning DangerousFile = new(name: "dangerousFile", engineWarning: EngineDownloadWarning.DangerousFile,
        confirms: false,
        approvalMessage: "This type of file can change your computer. Keep it only if you trust its source.",
        failure: DownloadFailure.BlockedUnsafe,
        coveredBy: [DownloadRiskReason.ExecutableOrInstaller, DownloadRiskReason.DangerousTypeMismatch]);
    public static readonly DownloadWarning UncommonContent = new(name: "uncommonContent",
        engineWarning: EngineDownloadWarning.UncommonContent, confirms: true,
        approvalMessage: "This file is not commonly downloaded. The engine could not confirm that it is safe.",
        failure: DownloadFailure.BlockedUnsafe);
    public static readonly DownloadWarning PotentiallyUnwanted = new(name: "potentiallyUnwanted",
        engineWarning: EngineDownloadWarning.PotentiallyUnwanted, confirms: true,
        approvalMessage: "This file may change your browser or computer settings without your permission.",
        failure: DownloadFailure.BlockedUnsafe);
    public static readonly DownloadWarning InsecureBlocked = new(name: "insecureBlocked",
        engineWarning: EngineDownloadWarning.InsecureBlocked, confirms: true,
        approvalMessage: "The engine blocked this insecure download.",
        failure: DownloadFailure.BlockedInsecure);
    public static readonly DownloadWarning PolicyBlocked = new(name: "policyBlocked", engineWarning: EngineDownloadWarning.PolicyBlocked,
        confirms: true,
        approvalMessage: "The engine blocked this download because of its safety or organization policy verdict.",
        failure: DownloadFailure.BlockedByPolicy);

    public static IReadOnlyList<DownloadWarning> All { get; } =
        [InsecureConnection, DangerousFile, UncommonContent, PotentiallyUnwanted, InsecureBlocked, PolicyBlocked];

    #endregion

    #region Variables

    public string Name { get; }

    /// The engine's warning this one stands for.
    public EngineDownloadWarning EngineWarning { get; }

    /// Whether the person must keep the file before the engine finishes it.
    /// The engine's warning that a file's type can run software is what
    /// `DownloadRiskReason.ExecutableOrInstaller` names, which is saved for
    /// the platform's quarantine and Gatekeeper to check, so it does not ask.
    /// An insecure connection, an uncommon file and a potentially unwanted one
    /// are verdicts about the transfer or the file itself, and ask.
    public bool Confirms { get; }

    /// What the person is told when Crest asks them to keep the file.
    [Localized]
    public string ApprovalMessage { get; }

    /// Why the download failed when the engine stopped it for the warning.
    public DownloadFailure Failure { get; }

    /// The core's risk reasons that already name what the engine warns
    /// about, so a person who kept the file for one of them is not asked
    /// again: a file whose type runs code.
    public IReadOnlyList<DownloadRiskReason> CoveredBy { get; }

    #endregion

    #region Constructors

    private DownloadWarning(string name, EngineDownloadWarning engineWarning, bool confirms, string approvalMessage,
        DownloadFailure failure, IReadOnlyList<DownloadRiskReason>? coveredBy = null) {
        Name = name;
        EngineWarning = engineWarning;
        Confirms = confirms;
        ApprovalMessage = approvalMessage;
        Failure = failure;
        CoveredBy = coveredBy ?? [];
    }

    #endregion

    #region Actions - Lookup

    public static DownloadWarning? Named(string? name) => All.FirstOrDefault(warning => warning.Name == name);

    /// The warning the engine's `reported` stands for.
    public static DownloadWarning Of(EngineDownloadWarning reported) => All.First(warning => warning.EngineWarning == reported);

    #endregion

    #region Actions - Risk

    /// Whether the core's `reasons` already named what the warning is about.
    public bool IsCoveredBy(IReadOnlyList<DownloadRiskReason> reasons) {
        ArgumentNullException.ThrowIfNull(reasons);
        return reasons.Any(CoveredBy.Contains);
    }

    /// Whether the person must keep the file before the engine finishes it,
    /// given the core's reasons they already kept it for.
    public bool RequiresConfirmation(IReadOnlyList<DownloadRiskReason> keptReasons) => Confirms && !IsCoveredBy(keptReasons);

    #endregion
}
