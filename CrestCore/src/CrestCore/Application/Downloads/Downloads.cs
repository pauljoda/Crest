using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The downloads area: this run's download ledger and the changes each
/// download intent publishes. An event that does not apply to a record's
/// phase publishes nothing. Nothing here is persisted or synced.
public sealed class Downloads {
    #region Variables

    private readonly DownloadLedger ledger = new();

    /// This run's downloads.
    internal DownloadLedger Ledger => ledger;

    #endregion

    #region Actions - Intents

    /// Runs one download intent, publishing each download it changed or removed.
    public void Handle(DownloadIntent intent, ChangeFeed changes) => intent.Apply(this, changes);

    /// Publishes `download` where the ledger holds it, when an event applied.
    internal void Updated(DownloadState? download, ChangeFeed changes) {
        if (download is not null) changes.Publish(new DownloadUpdated(download, ledger.IndexOf(download.Id)));
    }

    /// Publishes the downloads the ledger let go, when there are any.
    internal static void Removed(IReadOnlyList<Guid> downloadIds, ChangeFeed changes) {
        if (downloadIds.Count > 0) changes.Publish(new DownloadsRemoved(downloadIds));
    }

    /// Removes the finished, canceled, failed and blocked records of the
    /// profiles `spaces` browse in whose age at `now` strictly exceeds their
    /// Space's download retention, publishing those it let go. When several
    /// Spaces share a profile the shortest retention wins; a profile with no
    /// limit keeps its records.
    internal void Expire(IEnumerable<SpaceState> spaces, DateTimeOffset now, ChangeFeed changes) =>
        Removed(ledger.RemoveExpired([.. spaces.Select(space => new DownloadRetention(space.ProfileId,
            space.Settings.BrowsingPreferences.DataRetention.Downloads.Lifetime))], now), changes);

    #endregion

    #region Actions - Queries

    /// How many downloads are still in progress.
    public int LiveCount => ledger.Items.Count(download => download.Phase.IsLive);

    public DownloadProgressReading Answer(DownloadProgress query) {
        ArgumentNullException.ThrowIfNull(query);
        return (query.Estimator ?? DownloadTransferEstimator.Initial).Sample(query.CompletedUnitCount, query.TotalUnitCount,
            query.FractionCompleted, query.IsPaused, query.Uptime);
    }

    public DownloadRiskVerdict Answer(DownloadRisk query) {
        ArgumentNullException.ThrowIfNull(query);
        var assessment = DownloadRiskAssessment.Of(query.Facts);
        return new(assessment, assessment.RequiresConfirmation(query.IsUserInitiated));
    }

    #endregion
}
