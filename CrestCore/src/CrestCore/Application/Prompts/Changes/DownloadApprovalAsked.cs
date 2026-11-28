namespace CrestCore.Contracts;

/// Whether to keep the file of the download `DownloadId` waits on the person:
/// the core's `Reasons` it looks dangerous, and the engine's `Warning` when the
/// engine warned about it. `SpaceId` is the Space it belongs to and
/// `SourceHost` the host it came from, when known.
public sealed record DownloadApprovalAsked(Guid PromptId, Guid DownloadId, Guid? SpaceId, string Filename,
    IReadOnlyList<DownloadRiskReason> Reasons, DownloadWarning? Warning, string? SourceHost) : Change {
    #region Actions - Prompts

    /// The prompt it asks, which waits until a `PromptSettled` for it.
    internal override Guid? AskedPromptId => PromptId;

    #endregion
}
