using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Actions - Cloud sync

    /// Runs one intent from the cloud transport on the session this core keeps
    /// in its file, on the calling thread, which is the transport's and never
    /// the host's; see `CloudSyncIntent`. A merge or replacement computes
    /// outside the lock and takes it only to commit, so every change it makes
    /// joins the pending batch at once, under the lock, and wakes the host once
    /// it lets go. An intent about the journal alone takes no lock the host's
    /// intents wait for. Answers the intent's receipts: `SyncRecordsSkipped`
    /// when it left records out.
    private IReadOnlyList<Change> Handle(CloudSyncIntent intent) {
        var session = StoredSyncSession();
        if (device.Identity(session) is null) throw new Rejected(new NoStoredSession());
        try {
            return session.Handle(intent, clock.Now, ids, gate);
        } finally {
            WakeIfOwed();
            WakeForRequestedTurn();
        }
    }

    private PendingUploadList Answer(PendingUploads query) => StoredSyncSession().Answer(query);

    private UploadBatch Answer(RecordsToUpload query) => StoredSyncSession().Answer(query);

    private CloudContentComparison Answer(CloudComparison query) => StoredSyncSession().Answer(query);

    /// Returns once every stage of the stored session's journal requested
    /// before the call has committed, failed or been superseded, without
    /// waiting for the host's turn or a coalescing delay, and at once while
    /// the file holds no session. It takes no lock the host's calls wait for,
    /// but it blocks, so the host never calls it on its UI thread.
    public void SettleSync() => storedSync?.Flush();

    /// The session this core keeps in its file, which the cloud transport
    /// syncs. Throws `Rejected` with `NoStoredSession` while the file holds
    /// none, and `StoredSessionClosed` once it closed.
    private NativeSessionAuthority StoredSyncSession() {
        if (storedSession is not { } session) throw new Rejected(new NoStoredSession());
        if (session.IsReleased) throw new Rejected(new StoredSessionClosed());
        return session;
    }

    #endregion
}
