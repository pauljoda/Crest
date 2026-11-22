namespace CrestCore.Contracts;

/// Where iCloud sync stands, and how the settings show it.
///
/// A phase travels as its index in `All`, so `All` is append-only.
public sealed class CloudSyncPhase {
    #region Variables

    public static readonly CloudSyncPhase Disabled = new(name: "disabled", isRetryable: false, title: "Off", symbol: "icloud.slash",
        tone: null, keepsCloudOutOfReach: false);
    public static readonly CloudSyncPhase Checking = new(name: "checking", isRetryable: false, title: "Checking iCloud",
        symbol: "arrow.triangle.2.circlepath.icloud", tone: StatusTone.Info, keepsCloudOutOfReach: true);
    /// Sync works, and this device's journal holds records that have not
    /// reached iCloud yet.
    public static readonly CloudSyncPhase WaitingToUpload = new(name: "waitingToUpload", isRetryable: false, title: "Waiting to upload",
        symbol: "icloud.and.arrow.up", tone: StatusTone.Info, keepsCloudOutOfReach: false);
    /// Sync works, and nothing on this device waits to upload.
    public static readonly CloudSyncPhase Ready = new(name: "ready", isRetryable: false, title: "Up to date", symbol: "checkmark.icloud.fill",
        tone: StatusTone.Success, keepsCloudOutOfReach: false, whileUploadsWait: WaitingToUpload);
    public static readonly CloudSyncPhase Syncing = new(name: "syncing", isRetryable: false, title: "Syncing",
        symbol: "arrow.triangle.2.circlepath.icloud", tone: StatusTone.Info, keepsCloudOutOfReach: false);
    public static readonly CloudSyncPhase NeedsReconciliation = new(name: "needsReconciliation", isRetryable: false,
        title: "Choose which copy to keep", symbol: "exclamationmark.icloud.fill", tone: StatusTone.Warning, keepsCloudOutOfReach: false);
    public static readonly CloudSyncPhase WaitingForAccount = new(name: "waitingForAccount", isRetryable: true, title: "Waiting for iCloud",
        symbol: "person.crop.circle.badge.exclamationmark", tone: StatusTone.Warning, keepsCloudOutOfReach: true);
    public static readonly CloudSyncPhase Failed = new(name: "failed", isRetryable: true, title: "Needs attention",
        symbol: "xmark.icloud.fill", tone: StatusTone.Danger, keepsCloudOutOfReach: true);

    public static IReadOnlyList<CloudSyncPhase> All { get; } =
        [Disabled, Checking, Ready, Syncing, NeedsReconciliation, WaitingForAccount, Failed, WaitingToUpload];

    public string Name { get; }

    /// Whether trying the same thing again could reach a different answer. A
    /// missing account and a failed launch both heal on their own once iCloud
    /// is reachable; everything else is working, in progress, or waiting on a
    /// decision only somebody using Crest can make.
    public bool IsRetryable { get; }

    /// What the settings call the phase.
    [Localized]
    public string Title { get; }

    /// The SF Symbol the settings show beside the phase.
    public string Symbol { get; }

    /// How the phase reads in the settings, or null for the quiet style of a
    /// phase that needs nothing.
    public StatusTone? Tone { get; }

    /// Whether iCloud's content is out of this device's reach: the check for
    /// it has not answered, no account is signed in, or sync failed.
    public bool KeepsCloudOutOfReach { get; }

    /// The phase this one reads as while records wait to upload, when it
    /// gives way to them: a sync that has nothing left to do is not up to
    /// date while this device's changes have not left it.
    internal CloudSyncPhase? WhileUploadsWait { get; }

    #endregion

    #region Constructors

    private CloudSyncPhase(string name, bool isRetryable, string title, string symbol, StatusTone? tone, bool keepsCloudOutOfReach,
        CloudSyncPhase? whileUploadsWait = null) {
        Name = name;
        IsRetryable = isRetryable;
        Title = title;
        Symbol = symbol;
        Tone = tone;
        KeepsCloudOutOfReach = keepsCloudOutOfReach;
        WhileUploadsWait = whileUploadsWait;
    }

    #endregion

    #region Actions - Presenting

    /// The phase the settings show while `pendingUploads` records wait to
    /// upload.
    internal CloudSyncPhase Showing(int pendingUploads) => pendingUploads > 0 && WhileUploadsWait is { } waiting ? waiting : this;

    #endregion
}
