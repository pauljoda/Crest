using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Variables

    private readonly SessionStorage? storage;

    /// The session this core keeps in its file, as it loaded and repaired it,
    /// once the file holds one. `OpenWorkspace` opens it.
    private NativeSessionAuthority? storedSession;
    /// The sync component the file's session stages into, kept beside it.
    private NativeSyncAuthority? storedSync;
    /// The selection an older release kept in the stored session, which the
    /// windows of the launch that loaded it adopt.
    private JsonObject? storedSelection;
    /// The tabs the repair gave a new identity, each with the tab whose image
    /// it wears.
    private IReadOnlyList<(Guid Source, Guid Copy)> repairedCopies = [];

    /// TRANSITIONAL until typed sync (slice 8): the sync component of the
    /// session this core keeps in its file, for the cloud transport's journal
    /// calls; null while the file holds no session.
    public NativeSyncAuthority? StoredSync {
        get {
            lock (gate) return storedSync;
        }
    }

    #endregion

    #region Actions - Stored session

    /// Gives a file that holds no session its first one, before returning:
    /// the installed release's, or the seed. See `AdoptLegacySession`.
    private void Adopt(AdoptLegacySession adoption, ChangeFeed changes) {
        if (storage is not { } target || storedSession is not null) return;
        // A file that holds a session this core could not take over is refused
        // at creation, so one found here was written by an adoption whose
        // takeover failed: it is as unreadable now as it was then.
        if (target.HoldsSession) throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        var first = FirstSession.For(adoption);
        try {
            if (first.RequestsCloudRecovery) target.RequestCloudRecovery();
            target.Install(first.Session, first.Journal);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        } catch (IOException) {
            throw new Rejected(new SaveFailed(StorageFailure.Unavailable));
        } catch (UnauthorizedAccessException) {
            throw new Rejected(new SaveFailed(StorageFailure.ReadOnly));
        }
        Establish(first.Session, first.Journal, first.LegacySelection);
        changes.Publish(new SessionAdopted(first.Favicons));
    }

    /// Replaces the session file in `configuration`'s directory with the
    /// recovery checkpoint the last good launch kept, while no core has that
    /// file open. Throws `Rejected` naming why it cannot; see
    /// `SessionStorage.Restore`.
    public static void RestoreRecoveryCheckpoint(AppConfiguration configuration) {
        ArgumentNullException.ThrowIfNull(configuration);
        if (configuration.StorageDirectory is not { } directory)
            throw new Rejected(new RecoveryCheckpointUnusable(StorageFailure.Unavailable));
        SessionStorage.Restore(directory);
    }

    /// Makes a stored session the one `OpenWorkspace` opens from the file. The
    /// recovery checkpoint preserves the file exactly as loaded before anything
    /// else is written; the repaired session is then the first save.
    private void Establish(SessionState stored, NativeSyncJournal? journal, JsonObject? legacySelection) {
        var target = storage!;
        try {
            target.SaveRecoveryCheckpoint();
        } catch (Exception error) when (error is StorageException or IOException or UnauthorizedAccessException) {
            // A launch that cannot preserve a copy still opens the session it read.
        }
        SessionState repaired;
        IReadOnlyList<NativeSessionMaintenance.TabOrigin> origins;
        try {
            repaired = NativeSessionMaintenance.Repair(stored, DateTimeOffset.UtcNow, null, new SystemIdSource(), out origins);
        } catch (BrowserRuleException) {
            throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        }
        storedSession = new NativeSessionAuthority(repaired, target);
        storedSync = new NativeSyncAuthority(journal ?? NativeSyncJournal.Fresh(Guid.NewGuid()));
        storedSelection = legacySelection;
        repairedCopies = [.. origins
            .Select(origin => (Source: origin.SourceTabId, Copy: repaired.Spaces[origin.SpaceIndex].Tabs[origin.TabIndex].Id))
            .Where(pair => pair.Source != pair.Copy)];
    }

    #endregion
}
