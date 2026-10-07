using CrestCore.Contracts;

namespace CrestCore.Application;

/// What each state an engine reports a download in means for its record. The
/// engine contract fixes `EngineDownloadState`'s spelling, so what the core
/// reads in one is declared here, and `Of` reads it; a report's handling still
/// switches over the state itself.
internal sealed class EngineDownloadStage {
    #region Static Variables

    public static readonly EngineDownloadStage Preparing = new(EngineDownloadState.Preparing, isUnderway: true);
    public static readonly EngineDownloadStage Downloading = new(EngineDownloadState.Downloading, isUnderway: true);
    public static readonly EngineDownloadStage AwaitingApproval = new(EngineDownloadState.AwaitingApproval, isUnderway: true);
    public static readonly EngineDownloadStage Finished = new(EngineDownloadState.Finished, isUnderway: true);
    public static readonly EngineDownloadStage Canceled = new(EngineDownloadState.Canceled, isUnderway: false);
    public static readonly EngineDownloadStage Failed = new(EngineDownloadState.Failed, isUnderway: false);
    public static readonly EngineDownloadStage Blocked = new(EngineDownloadState.Blocked, isUnderway: false);

    public static IReadOnlyList<EngineDownloadStage> All { get; } =
        [Preparing, Downloading, AwaitingApproval, Finished, Canceled, Failed, Blocked];

    #endregion

    #region Variables

    /// The state the engine reports.
    public EngineDownloadState State { get; }

    /// The engine carries the download on, or finished it, rather than
    /// stopping it: a report in such a state takes up a download the person
    /// asked to resume.
    public bool IsUnderway { get; }

    #endregion

    #region Constructors

    private EngineDownloadStage(EngineDownloadState state, bool isUnderway) {
        State = state;
        IsUnderway = isUnderway;
    }

    #endregion

    #region Actions - Lookup

    /// The stage the engine's `reported` state stands for.
    public static EngineDownloadStage Of(EngineDownloadState reported) => All.First(stage => stage.State == reported);

    #endregion
}
