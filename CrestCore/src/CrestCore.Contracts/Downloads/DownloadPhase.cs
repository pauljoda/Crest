namespace CrestCore.Contracts;

/// Where one download record stands. Preparing, awaiting approval and
/// downloading are live transfers; a blocked automatic download waits for the
/// person to retry it; finished, canceled and failed records are final.
public enum DownloadPhase { Preparing, AwaitingApproval, Downloading, Finished, BlockedAutomaticDownload, Canceled, Failed }
