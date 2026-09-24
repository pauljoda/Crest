using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Variables

    private const string LegacySelectionField = "legacySelection";

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
    /// and repaired, `{"session", "assets", "legacySelection"}`, read with the
    /// command API. `assets` names the tab each repaired tab's native images
    /// came from; `legacySelection` is the selection an older release stored.
    public NativeSessionCommand? SessionProjection() {
        lock (gate) return Session is { } session && launchProjection is { } bytes ? session.Projection(bytes) : null;
    }

    /// TRANSITIONAL until the core migrates the legacy session itself (3b):
    /// writes the first session, in the stored format with each Space's
    /// history, and the journal that goes with it, into a file that holds no
    /// session yet, then loads it as a launch would. Throws
    /// `InvalidOperationException` when there is no file or it already holds
    /// a session, and `StorageException` when the write fails.
    public void InstallSession(ReadOnlySpan<byte> session, ReadOnlySpan<byte> journal) {
        var target = storage ?? throw new InvalidOperationException("This core keeps nothing in storage.");
        if (session.IsEmpty || session.Length > NativeSessionAuthority.MaximumBytes)
            throw new BrowserRuleException(BrowserRuleCodes.SessionSizeLimit);
        var decoded = StoredSessionCodec.DecodeSession(JsonNode.Parse(session, documentOptions: new() { MaxDepth = 64 }));
        var decodedJournal = journal.IsEmpty ? null : new NativeSyncJournal(journal);
        lock (gate) {
            if (Session is not null) throw new InvalidOperationException("The session file already holds a session.");
            target.Install(decoded, decodedJournal);
            Establish(decoded, decodedJournal, legacySelection: null);
        }
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
        var projection = NativeSessionMaintenance.Answer(repaired, origins);
        if (legacySelection is not null) projection[LegacySelectionField] = legacySelection;
        launchProjection = Encoding.UTF8.GetBytes(projection.ToJsonString());
        Session = session;
        SessionSync = sync;
    }

    #endregion
}
