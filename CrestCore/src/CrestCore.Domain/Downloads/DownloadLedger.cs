namespace CrestCore.Domain;

/// The process-local record of this run's downloads, newest first.
///
/// Engines report transfer events and the ledger decides what each event
/// means for the record: live transfers accept progress, destinations, risk
/// verdicts and a final outcome; a blocked automatic download may only be
/// retried or failed; finished, canceled and failed records only expire or are
/// removed. An event that does not apply to the record's state is ignored and
/// reported as not applied, so a late engine callback cannot revive a record.
/// Nothing here is persisted or synced. Callers serialize access.
public sealed class DownloadLedger {
    #region Variables

    public const int MaximumItems = 10_000;
    public const int MaximumFilenameLength = 1_024;
    public const int MaximumDestinationLength = 8_192;
    public const int MaximumMessageLength = 2_048;

    private readonly List<DownloadItem> items = [];

    public IReadOnlyList<DownloadItem> Items => items;

    #endregion

    #region Actions - Ordering

    /// Records a new download as preparing, ahead of every existing record. The
    /// caller supplies the identity and creation time so a retried call is
    /// deterministic. A download restored by an engine starts acknowledged.
    public DownloadItem Begin(Guid id, Guid profile, string filename, double createdAt, bool isAcknowledged) {
        if (id == Guid.Empty || profile == Guid.Empty) throw new BrowserRuleException(BrowserRuleCodes.InvalidIdentity);
        if (!double.IsFinite(createdAt)) throw new BrowserRuleException(BrowserRuleCodes.InvalidRecordDate);
        ValidateText(filename, MaximumFilenameLength, BrowserRuleCodes.InvalidDownloadFilename);
        if (IndexOf(id) >= 0) throw new BrowserRuleException(BrowserRuleCodes.DuplicateDownload);
        if (items.Count >= MaximumItems) throw new BrowserRuleException(BrowserRuleCodes.DownloadLedgerLimit);
        var item = new DownloadItem(id, profile, createdAt, filename, null, 0, DownloadTelemetry.Empty,
            DownloadItemState.Preparing, null, null, isAcknowledged);
        items.Insert(0, item);
        return item;
    }

    public int IndexOf(Guid id) => items.FindIndex(item => item.Id == id);

    #endregion

    #region Actions - Transfers

    /// The destination names the file, so the record's filename follows it.
    public DownloadItem? SetDestination(Guid id, string destination, string filename) {
        ValidateText(destination, MaximumDestinationLength, BrowserRuleCodes.InvalidDownloadDestination);
        ValidateText(filename, MaximumFilenameLength, BrowserRuleCodes.InvalidDownloadFilename);
        return UpdateActive(id, item => item with { Destination = destination, Filename = filename, State = DownloadItemState.Downloading });
    }

    /// Progress never moves backwards while a transfer is live.
    public DownloadItem? RecordTransfer(Guid id, DownloadTelemetry telemetry, double progress) {
        ArgumentNullException.ThrowIfNull(telemetry);
        if (!telemetry.IsValid || !double.IsFinite(progress)) throw new BrowserRuleException(BrowserRuleCodes.InvalidDownloadProgress);
        return UpdateActive(id, item => item with {
            Telemetry = telemetry,
            Progress = Math.Max(item.Progress, DownloadTransferEstimator.Normalized(progress))
        });
    }

    /// A download with any risk reason waits for approval under its sanitized name.
    public DownloadItem? AssessRisk(Guid id, DownloadRiskAssessment assessment) {
        ArgumentNullException.ThrowIfNull(assessment);
        ValidateText(assessment.SanitizedFilename, MaximumFilenameLength, BrowserRuleCodes.InvalidDownloadFilename);
        return UpdateActive(id, item => item with {
            Filename = assessment.SanitizedFilename,
            Risk = assessment,
            State = assessment.Reasons.Count > 0 ? DownloadItemState.AwaitingApproval : item.State
        });
    }

    public DownloadItem? AwaitApproval(Guid id) =>
        UpdateActive(id, item => item with { State = DownloadItemState.AwaitingApproval });

    public DownloadItem? Finish(Guid id, long? finalByteCount) {
        if (finalByteCount < 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidDownloadProgress);
        return UpdateActive(id, item => item with {
            Progress = 1,
            Telemetry = item.Telemetry.Stopped(finalByteCount, completed: true),
            State = DownloadItemState.Finished
        });
    }

    public DownloadItem? Cancel(Guid id, string message) {
        ValidateText(message, MaximumMessageLength, BrowserRuleCodes.InvalidDownloadMessage);
        return UpdateActive(id, item => Stopped(item, DownloadItemState.Canceled, message));
    }

    /// A blocked automatic download may also fail, when its retry can no longer
    /// be replayed.
    public DownloadItem? Fail(Guid id, string message) {
        ValidateText(message, MaximumMessageLength, BrowserRuleCodes.InvalidDownloadMessage);
        return Update(id, item => item.IsActive || item.State == DownloadItemState.BlockedAutomaticDownload,
            item => Stopped(item, DownloadItemState.Failed, message));
    }

    public DownloadItem? BlockAutomaticDownload(Guid id) =>
        UpdateActive(id, item => Stopped(item, DownloadItemState.BlockedAutomaticDownload, null));

    /// Retrying a blocked automatic download starts the same record again from
    /// nothing and counts as news for the downloads badge.
    public DownloadItem? Restart(Guid id) =>
        Update(id, item => item.State == DownloadItemState.BlockedAutomaticDownload, item => item with {
            Destination = null,
            Progress = 0,
            Telemetry = DownloadTelemetry.Empty,
            State = DownloadItemState.Preparing,
            Message = null,
            Risk = null,
            IsAcknowledged = false
        });

    #endregion

    #region Actions - Acknowledgement

    /// Opening a profile's downloads acknowledges its records without clearing
    /// them. Returns the records that were newly acknowledged.
    public IReadOnlyList<DownloadItem> AcknowledgeProfile(Guid profile) {
        var acknowledged = new List<DownloadItem>();
        for (int index = 0; index < items.Count; index++) {
            if (items[index].Profile != profile || items[index].IsAcknowledged) continue;
            items[index] = items[index] with { IsAcknowledged = true };
            acknowledged.Add(items[index]);
        }
        return acknowledged;
    }

    #endregion

    #region Actions - Expiry

    /// Clearing removes only a record; files already written stay on disk. The
    /// caller refuses to clear a record whose transfer it still owns.
    public bool Remove(Guid id) {
        int index = IndexOf(id);
        if (index < 0) return false;
        items.RemoveAt(index);
        return true;
    }

    /// Deleting a profile's data removes every record it owns, live or not; the
    /// caller cancels the matching transfers.
    public IReadOnlyList<Guid> RemoveProfile(Guid profile) => RemoveWhere(item => item.Profile == profile);

    /// Removes records whose age strictly exceeds their profile's retention.
    /// When several Spaces share a profile the shortest retention wins; a
    /// profile with no limit keeps its records. Live transfers never expire.
    public IReadOnlyList<Guid> RemoveExpired(IReadOnlyList<DownloadRetentionLimit> limits, double now) {
        ArgumentNullException.ThrowIfNull(limits);
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidRetentionInterval);
        var lifetimes = new Dictionary<Guid, double?>();
        foreach (var limit in limits) {
            if (limit.Lifetime is { } seconds && (!double.IsFinite(seconds) || seconds < 0))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidRetentionInterval);
            lifetimes[limit.Profile] = lifetimes.TryGetValue(limit.Profile, out var existing)
                ? Shorter(existing, limit.Lifetime)
                : limit.Lifetime;
        }
        return RemoveWhere(item => !item.IsActive && lifetimes.TryGetValue(item.Profile, out var lifetime)
            && lifetime is { } seconds && now - item.CreatedAt > seconds);
    }

    private static double? Shorter(double? existing, double? proposed) =>
        existing is not { } current ? proposed : proposed is not { } next ? current : Math.Min(current, next);

    private List<Guid> RemoveWhere(Predicate<DownloadItem> predicate) {
        var removed = items.Where(item => predicate(item)).Select(item => item.Id).ToList();
        items.RemoveAll(predicate);
        return removed;
    }

    #endregion

    #region Actions - Transitions

    private static DownloadItem Stopped(DownloadItem item, DownloadItemState state, string? message) =>
        item with { Telemetry = item.Telemetry.Stopped(), State = state, Message = message };

    private DownloadItem? UpdateActive(Guid id, Func<DownloadItem, DownloadItem> transition) =>
        Update(id, item => item.IsActive, transition);

    private DownloadItem? Update(Guid id, Func<DownloadItem, bool> accepts, Func<DownloadItem, DownloadItem> transition) {
        int index = IndexOf(id);
        if (index < 0 || !accepts(items[index])) return null;
        items[index] = transition(items[index]);
        return items[index];
    }

    private static void ValidateText(string? value, int maximumLength, string code) {
        if (string.IsNullOrEmpty(value) || value.Length > maximumLength) throw new BrowserRuleException(code);
    }

    #endregion
}
