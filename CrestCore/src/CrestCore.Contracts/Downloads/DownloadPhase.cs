namespace CrestCore.Contracts;

/// Where one download record stands. Live phases belong to a transfer that an
/// engine or a pending prompt still owns; a blocked automatic download waits
/// for the person to retry it; finished, canceled and failed records are final.
///
/// A phase travels as its index in `All`, so `All` is append-only.
public sealed class DownloadPhase {
    #region Variables

    public static readonly DownloadPhase Preparing = new(name: "preparing", isLive: true);
    public static readonly DownloadPhase AwaitingApproval = new(name: "awaitingApproval", isLive: true);
    public static readonly DownloadPhase Downloading = new(name: "downloading", isLive: true, isTransferring: true);
    public static readonly DownloadPhase Finished = new(name: "finished", isComplete: true);
    public static readonly DownloadPhase BlockedAutomaticDownload = new(name: "blockedAutomaticDownload", needsAttention: true,
        canRetry: true);
    public static readonly DownloadPhase Canceled = new(name: "canceled");
    public static readonly DownloadPhase Failed = new(name: "failed", needsAttention: true);

    public static IReadOnlyList<DownloadPhase> All { get; } =
        [Preparing, AwaitingApproval, Downloading, Finished, BlockedAutomaticDownload, Canceled, Failed];

    public string Name { get; }

    /// A transfer an engine or a pending prompt still owns. Only a live record
    /// accepts transfer events and cancellation, and it never expires.
    public bool IsLive { get; }

    /// Bytes are arriving, so a rate and a time remaining mean something.
    public bool IsTransferring { get; }

    /// The file is saved in full at the record's destination.
    public bool IsComplete { get; }

    /// The download failed or is blocked, so the person should look.
    public bool NeedsAttention { get; }

    /// Retrying starts the same record again from nothing.
    public bool CanRetry { get; }

    /// A live transfer can fail, and so can a record whose retry can no longer
    /// be replayed.
    public bool CanFail => IsLive || CanRetry;

    #endregion

    #region Constructors

    private DownloadPhase(string name, bool isLive = false, bool isTransferring = false, bool isComplete = false,
        bool needsAttention = false, bool canRetry = false) {
        Name = name;
        IsLive = isLive;
        IsTransferring = isTransferring;
        IsComplete = isComplete;
        NeedsAttention = needsAttention;
        CanRetry = canRetry;
    }

    #endregion

    #region Actions - Lookup

    public static DownloadPhase? Named(string? name) => All.FirstOrDefault(phase => phase.Name == name);

    #endregion
}
