using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The downloads area: this run's download ledger and the changes each
/// download intent publishes. An event that does not apply to a record's
/// phase publishes nothing. Nothing here is persisted or synced.
public sealed class Downloads {
    #region Variables

    private readonly DownloadLedger ledger = new();

    #endregion

    #region Actions - Intents

    public void Handle(DownloadIntent intent, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(changes);
        switch (intent) {
            case BeginDownload begin:
                Updated(ledger.Begin(begin.DownloadId, begin.ProfileId, begin.Filename, begin.CreatedAt, begin.IsAcknowledged), changes);
                break;
            case SetDownloadDestination destination:
                Updated(ledger.SetDestination(destination.DownloadId, destination.Destination, destination.Filename), changes);
                break;
            case RecordDownloadTransfer transfer:
                Updated(ledger.RecordTransfer(transfer.DownloadId, transfer.Telemetry, transfer.Progress), changes);
                break;
            case AssessDownloadRisk risk:
                Updated(ledger.AssessRisk(risk.DownloadId, risk.Assessment), changes);
                break;
            case AwaitDownloadApproval approval:
                Updated(ledger.AwaitApproval(approval.DownloadId), changes);
                break;
            case FinishDownload finish:
                Updated(ledger.Finish(finish.DownloadId, finish.FinalByteCount), changes);
                break;
            case FailDownload failure:
                Updated(ledger.Fail(failure.DownloadId, failure.Message), changes);
                break;
            case CancelDownload cancellation:
                Updated(ledger.Cancel(cancellation.DownloadId, cancellation.Message), changes);
                break;
            case BlockAutomaticDownload block:
                Updated(ledger.BlockAutomaticDownload(block.DownloadId), changes);
                break;
            case RestartDownload restart:
                Updated(ledger.Restart(restart.DownloadId), changes);
                break;
            case AcknowledgeDownloads acknowledgement:
                foreach (var download in ledger.AcknowledgeProfile(acknowledgement.ProfileId)) Updated(download, changes);
                break;
            case RemoveDownload removal:
                Removed(ledger.Remove(removal.DownloadId) ? [removal.DownloadId] : [], changes);
                break;
            case RemoveProfileDownloads profileRemoval:
                Removed(ledger.RemoveProfile(profileRemoval.ProfileId), changes);
                break;
            case ExpireDownloads expiry:
                Removed(ledger.RemoveExpired(expiry.Retentions, expiry.Now), changes);
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "Downloads does not handle this intent.");
        }
    }

    private void Updated(DownloadState? download, ChangeFeed changes) {
        if (download is not null) changes.Publish(new DownloadUpdated(download, ledger.IndexOf(download.Id)));
    }

    private static void Removed(IReadOnlyList<Guid> downloadIds, ChangeFeed changes) {
        if (downloadIds.Count > 0) changes.Publish(new DownloadsRemoved(downloadIds));
    }

    #endregion

    #region Actions - Queries

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
