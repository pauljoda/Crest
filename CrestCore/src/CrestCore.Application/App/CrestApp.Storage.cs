using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Variables

    private readonly SessionStorage? storage;
    private byte[]? launchProjection;

    /// TRANSITIONAL until session intents land: the persistent session this
    /// core keeps in storage, once the file holds one. The JSON command path
    /// reaches it through this authority.
    public NativeSessionAuthority? Session { get; private set; }
    /// TRANSITIONAL, with `Session`: the sync component attached to it.
    public NativeSyncAuthority? SessionSync { get; private set; }

    #endregion

    #region Actions - Stored session

    /// TRANSITIONAL until session intents land: the session as it was loaded
    /// and repaired, `{"session", "assets"}`, read with the command API.
    /// `assets` names the tab each repaired tab's native images came from.
    public NativeSessionCommand? SessionProjection() {
        lock (gate) return Session is { } session && launchProjection is { } bytes ? session.Projection(bytes) : null;
    }

    /// Gives a file that holds no session its first one, before returning:
    /// the installed release's, or the seed. See `AdoptLegacySession`.
    private void Adopt(AdoptLegacySession adoption, ChangeFeed changes) {
        if (storage is not { } target || Session is not null) return;
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

    /// Makes a stored session the core's persistent session. The recovery
    /// checkpoint preserves the file exactly as loaded before anything else is
    /// written; the repaired session is then the first save.
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
        var sync = new NativeSyncAuthority(journal ?? NativeSyncJournal.Fresh(Guid.NewGuid()));
        var session = new NativeSessionAuthority(repaired, target);
        session.AttachSync(sync);
        launchProjection = Encoding.UTF8.GetBytes(NativeSessionMaintenance.Answer(repaired, origins).ToJsonString());
        Session = session;
        SessionSync = sync;
        device.AttachPersistent(session, legacySelection);
    }

    #endregion
}
