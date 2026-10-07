using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// An engine download started, progressed, finished or failed. The core
/// records it in the download ledger, in the Space its page or profile belongs
/// to, and asks the person to keep a file the engine warned about.
public sealed record EngineDownloadChanged(EngineDownload Download) : EngineDownloadEvent(Download) {
    #region Actions - Downloads

    internal override void Apply(EngineDownloads engineDownloads, Engine engine, EngineDownloadTurn turn) {
        if (engineDownloads.Track(engine, Download, turn.Changes, turn.Now) is not { } download) {
            turn.Issue(engine, new CancelEngineDownload(Download.ProfileId, Download.DownloadId));
            return;
        }
        if (download.ResumeRequested) {
            download.ResumeRequested = false;
            if (!download.IsLive && EngineDownloadStage.Of(Download.State).IsUnderway) engineDownloads.Resume(download, turn.Changes);
        }
        if (!download.IsLive) return;
        download.LastReport = Download;
        if (Download.Path is { Length: > 0 } path) {
            var destination = new SetDownloadDestination(download.DownloadId, EngineDownloads.FileAddress(path), Path.GetFileName(path));
            engineDownloads.Record(destination, turn.Changes);
        }
        var sample = new DownloadProgress(download.Estimator, Download.Received, Download.Total,
            Download.Total > 0 ? (double)Download.Received / Download.Total : 0, Download.Paused, EngineDownloads.Uptime);
        if (engineDownloads.Sample(sample) is { } reading) {
            download.Estimator = reading.Estimator;
            engineDownloads.Record(new RecordDownloadTransfer(download.DownloadId, reading.Telemetry, reading.Progress), turn.Changes);
        }
        switch (Download.State) {
            case EngineDownloadState.Preparing or EngineDownloadState.Downloading:
                // A warning the person or the engine resolved asks nothing more.
                engineDownloads.SettleApproval(download, turn.Changes);
                break;
            case EngineDownloadState.Finished:
                engineDownloads.Record(new FinishDownload(download.DownloadId, Download.Received), turn.Changes);
                engineDownloads.End(download, turn.Changes);
                break;
            case EngineDownloadState.Canceled:
                engineDownloads.Record(new CancelDownload(download.DownloadId, EngineDownloads.CanceledMessage), turn.Changes);
                engineDownloads.End(download, turn.Changes);
                break;
            case EngineDownloadState.Failed:
                engineDownloads.Record(new FailDownload(download.DownloadId, EngineDownloads.FailureOf(Download), Download.FailureDetail),
                    turn.Changes);
                engineDownloads.End(download, turn.Changes);
                break;
            case EngineDownloadState.AwaitingApproval when Download.Warning is null:
                // An approval with nothing to approve is never kept.
                turn.Issue(engine, new CancelEngineDownload(download.ProfileId, download.EngineId));
                break;
            case EngineDownloadState.AwaitingApproval when Download.Warning is { } warning
                && download.ReasonsApproved && DownloadWarning.Of(warning).IsCoveredBy(download.Reasons):
                // A warning about what the person already kept asks nothing new.
                if (download.ApprovalToken == Download.ApprovalToken) break;
                download.ApprovalToken = Download.ApprovalToken;
                turn.Issue(engine, new ApproveEngineDownload(download.ProfileId, download.EngineId, Download.ApprovalToken));
                break;
            case EngineDownloadState.AwaitingApproval when Download.Warning is { } warning:
                engineDownloads.Record(new AwaitDownloadApproval(download.DownloadId), turn.Changes);
                if (download.ApprovalToken == Download.ApprovalToken) break;
                engineDownloads.SettleApproval(download, turn.Changes);
                download.ApprovalToken = Download.ApprovalToken;
                var prompt = engineDownloads.Ids.Next();
                engineDownloads.WaitingPrompts[prompt] = new(download, EngineDownloads.Question.Approval);
                turn.Changes.Publish(new DownloadApprovalAsked(prompt, download.DownloadId, engineDownloads.SpaceOf(Download),
                    DownloadFilename.Safe(Download.Filename), download.Reasons, DownloadWarning.Of(warning), download.SourceHost));
                break;
            case EngineDownloadState.Blocked:
                engineDownloads.Record(new BlockAutomaticDownload(download.DownloadId), turn.Changes);
                download.IsBlocked = true;
                download.ApprovalToken = Download.ApprovalToken;
                break;
        }
        engineDownloads.SetControls(download, Download, turn.Changes);
    }

    #endregion
}
