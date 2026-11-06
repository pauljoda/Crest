using CrestCore.Application;

namespace CrestCore.Contracts;

/// <summary>Which file revision the core has handed its session file and not yet
/// written, so a caller can wait until it is on disk. The stored session's edits
/// and this device's saved windows each take one. Asking has the file write it
/// without waiting for later edits to gather, and retry what a failed write left.</summary>
public sealed record PendingSave : Query<PendingSaveRevision> {
    #region Actions - Answering

    internal override PendingSaveRevision Answer(CrestApp app) {
        app.Storage?.Expedite();
        return new(app.Storage?.PendingRevision is { } revision ? checked((long)revision) : null);
    }

    #endregion
}
