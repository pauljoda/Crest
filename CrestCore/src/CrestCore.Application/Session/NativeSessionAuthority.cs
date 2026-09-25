using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

using Key = CrestCore.Application.StoredSessionCodec.Key;

namespace CrestCore.Application;

/// Owns the native app's durable session as typed records. Intents edit it; only
/// an accepted state becomes visible, and the device publishes what each accepted
/// state changed. Accepted states are immutable, so storage can serialize an older
/// checkpoint on its worker while the UI continues editing the current one. An
/// intent is accepted, or reserved while it is saved, under the lock that computed
/// its edit, so it never overwrites a change it did not see; nothing outside the
/// core names a revision. The session holds browsing data only: which Space and
/// tab a window shows is window state, so selection fields in an older session are
/// dropped here and never written. Intents read what the window shows as context.
public sealed partial class NativeSessionAuthority {
    #region Variables

    public const int MaximumBytes = 64 * 1024 * 1024;
    internal static readonly object Gate = new();
    private SessionState session;
    private NativeSessionReplacement? replacement;
    private readonly WorkspaceKind workspaceKind;
    private readonly bool privateBrowsing;
    /// The file a persistent session the core loaded keeps; null in memory.
    private readonly SessionStorage? storage;
    /// Counts the accepted states, so storage saves them in order and `Saved`
    /// can name the newest on disk.
    internal ulong Revision { get; private set; } = 1;

    /// What kind of workspace this session is.
    internal WorkspaceKind Kind => workspaceKind;

    #endregion

    #region Constructors

    /// A memory-only session of `kind` that starts as `initial` and keeps
    /// nothing: it is never saved or synced.
    internal NativeSessionAuthority(WorkspaceKind kind, SessionState initial) {
        ArgumentNullException.ThrowIfNull(kind);
        ArgumentNullException.ThrowIfNull(initial);
        workspaceKind = kind;
        privateBrowsing = kind.IsPrivate;
        session = initial;
        Validate(session);
    }

    /// The persistent session the core loaded from `storage` and repaired.
    /// Every revision it accepts is saved there.
    internal NativeSessionAuthority(SessionState stored, SessionStorage storage) {
        workspaceKind = WorkspaceKind.Persistent;
        session = stored;
        Validate(session);
        this.storage = storage;
        storage.Enqueue(session, Revision);
    }

    #endregion

    #region Actions - Session validation

    internal static Guid Id(JsonNode? value) {
        if (value is JsonObject obj) value = obj[Key.RawValue];
        var id = Guid.Parse(value!.GetValue<string>());
        if (id == Guid.Empty) throw new BrowserRuleException(BrowserRuleCodes.InvalidIdentity);
        return id;
    }

    /// Throws `Rejected` with `InvalidSession` unless `value` is a session a
    /// workspace can hold; see `Flaw`.
    private static void Validate(SessionState value) {
        if (Flaw(value) is { } flaw) throw new Rejected(new InvalidSession(flaw));
    }

    /// The first rule `value` breaks that keeps a workspace from holding it, or
    /// null for a session a workspace can hold.
    internal static SessionFlaw? Flaw(SessionState value) {
        var spaces = value.Spaces;
        var ids = new HashSet<Guid>(); var tabs = new HashSet<Guid>(); var profiles = new HashSet<Guid>();
        foreach (var space in spaces) {
            if (space.Id == Guid.Empty || space.ProfileId == Guid.Empty || space.Tabs.Any(tab => tab.Id == Guid.Empty))
                return SessionFlaw.MissingIdentity;
            if (!ids.Add(space.Id)) return SessionFlaw.DuplicateSpace;
            // A Space is exactly one profile and a profile belongs to exactly one
            // Space. Two Spaces sharing a profile would share cookies, credentials
            // and extension access across an isolation boundary the user relies on,
            // and would make "which Space owns this profile" unanswerable.
            if (!profiles.Add(space.ProfileId)) return SessionFlaw.SharedProfile;
            foreach (var tab in space.Tabs)
                if (!tabs.Add(tab.Id)) return SessionFlaw.DuplicateTab;
        }
        var pendingIds = new HashSet<Guid>();
        foreach (var deletion in value.SpaceDeletions) {
            if (deletion.Id == Guid.Empty || deletion.SpaceId == Guid.Empty || deletion.ProfileId == Guid.Empty)
                return SessionFlaw.MissingIdentity;
            if (!pendingIds.Add(deletion.SpaceId) || !spaces.Any(s => s.Id == deletion.SpaceId && s.ProfileId == deletion.ProfileId))
                return SessionFlaw.UnknownDeletion;
        }
        // An empty temporary workspace and a briefly stale window selection are
        // valid native states. Window reconciliation handles their presentation.
        return null;
    }

    /// A Space's settings without its records, as settings commands answer them.
    /// Split metadata stays: windows read it with the settings.
    private static SpaceState Settings(SpaceState space) => space with { Tabs = [], Folders = [], ArchivedTabs = [], History = [] };

    private static SessionState Replacing(SessionState session, params SpaceState[] edited) => session with {
        Spaces = session.Spaces.Select(space => edited.FirstOrDefault(value => value.Id == space.Id) ?? space).ToArray()
    };

    #endregion

    #region Actions - Session revisions

    private void RequireWritable(bool requireCurrentBorrowedPolicy = true) {
        if (released) throw new BrowserRuleException(BrowserRuleCodes.SessionReleased);
        if (replacement is not null) throw new BrowserRuleException(BrowserRuleCodes.SessionTransactionInProgress);
        if (borrowedSource is not null) {
            _ = RequireBorrowedSource();
            if (requireCurrentBorrowedPolicy) RequireCurrentBorrowedPolicy(session);
        }
    }

    /// Makes `next` the accepted state, saved behind as a new revision, and
    /// answers the state it replaced. The caller holds the gate.
    private SessionState Accept(SessionState next) {
        var previous = session;
        session = next;
        Revision = checked(Revision + 1);
        storage?.Enqueue(session, Revision);
        return previous;
    }

    /// The stored parts of the accepted state.
    internal NativeSessionCheckpoint Checkpoint() {
        lock (Gate) return new(session);
    }

    #endregion
}
