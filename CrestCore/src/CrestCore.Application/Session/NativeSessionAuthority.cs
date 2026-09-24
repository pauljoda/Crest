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

    private static JsonObject Parse(ReadOnlySpan<byte> bytes) {
        if (bytes.Length == 0 || bytes.Length > MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionSizeLimit);
        return JsonNode.Parse(bytes, documentOptions: new() { MaxDepth = 64 })!.AsObject();
    }

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

    private SessionState Prepare(ReadOnlySpan<byte> bytes, IReadOnlyList<SpaceDeletionState>? authorizedDeletions = null,
        bool nativeValueEdit = false) {
        RequireWritable();
        var delta = Parse(bytes);
        if (delta["version"]!.GetValue<int>() != 1) throw new BrowserRuleException(BrowserRuleCodes.VersionMismatch);
        // Only the preference commands change the app preferences, so a value
        // edit or a sync replacement keeps the owned ones.
        var settings = delta["metadata"] is JsonObject suppliedSettings
            ? StoredSessionCodec.DecodeSessionSettings(suppliedSettings) with { AppPreferences = session.AppPreferences }
            : session;
        if (!SameDeletions(settings.SpaceDeletions, authorizedDeletions ?? session.SpaceDeletions))
            throw new BrowserRuleException(BrowserRuleCodes.DeletionRequiresCommand);
        var byId = session.Spaces.ToDictionary(s => s.Id);
        var proposed = new List<Guid>();
        foreach (var node in delta["spaces"]!.AsArray()) {
            var change = node!.AsObject(); var id = Id(change["id"]);
            proposed.Add(id);
            byId.TryGetValue(id, out var original);
            var supplied = change["metadata"] is JsonObject fields ? StoredSessionCodec.DecodeSpace(fields) : null;
            if ((supplied ?? original) is not { } space || space.Id != id)
                throw new BrowserRuleException(BrowserRuleCodes.WrongSpaceIdentity);
            byId[id] = space with {
                Tabs = Edited(original?.Tabs, change[Key.Tabs], StoredSessionCodec.DecodeTab, tab => tab.Id),
                Folders = Edited(original?.Folders, change[Key.Folders], StoredSessionCodec.DecodeFolder, folder => folder.Id),
                SplitGroups = supplied?.SplitGroups ?? original!.SplitGroups,
                ArchivedTabs = Edited(original?.ArchivedTabs, change[Key.ArchivedTabs], StoredSessionCodec.DecodeArchivedTab,
                    archived => archived.Tab.Id),
                History = Edited(original?.History, change[Key.History], StoredSessionCodec.DecodeHistoryEntry, entry => entry.Id)
            };
        }
        var spaceOrder = delta["spaceOrder"] is JsonArray suppliedOrder
            ? suppliedOrder.Select(Id).ToArray() : session.Spaces.Select(s => s.Id).ToArray();
        if (spaceOrder.Distinct().Count() != spaceOrder.Length || spaceOrder.Any(id => !byId.ContainsKey(id)))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidSpaceOrder);
        var next = settings with { Spaces = spaceOrder.Select(id => byId[id]).ToArray() };
        if (!session.SpaceDeletions.All(settings.SpaceDeletions.Contains))
            throw new BrowserRuleException(BrowserRuleCodes.DeletionRequiresCommand);
        // A Space that is being deleted stays exactly as it was until it is removed.
        foreach (var deletion in settings.SpaceDeletions) {
            var original = session.Spaces.Single(s => s.Id == deletion.SpaceId);
            var retained = next.Spaces.SingleOrDefault(s => s.Id == deletion.SpaceId);
            if (retained is null || original != retained)
                throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        }
        Validate(next);
        ValidateBorrowedSession(next);
        if (nativeValueEdit) RequireAccessibleValueEdit(next, proposed);
        return next;
    }

    /// One record collection after a delta's edit: a whole replacement, or
    /// removals and upserts by identity in the order it names, else the
    /// collection's own order.
    private static IReadOnlyList<T> Edited<T>(IReadOnlyList<T>? original, JsonNode? edit, Func<JsonNode?, T> decode,
        Func<T, Guid> identity) {
        var previous = original ?? [];
        if (edit is not JsonObject edits) return previous;
        if (edits["replace"] is JsonArray replacement) return replacement.Select(decode).ToArray();
        var records = previous.ToDictionary(identity);
        foreach (var removed in edits["remove"]!.AsArray()) records.Remove(Id(removed));
        foreach (var item in edits["upsert"]!.AsArray()) { var record = decode(item); records[identity(record)] = record; }
        var order = edits["order"] is JsonArray supplied ? supplied.Select(Id).ToArray() : previous.Select(identity).ToArray();
        if (order.Length != records.Count || order.Distinct().Count() != order.Length || order.Any(id => !records.ContainsKey(id)))
            throw new BrowserRuleException(BrowserRuleCodes.InvalidRecordOrder);
        return order.Select(id => records[id]).ToArray();
    }

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

    /// `nativeValueEdit` marks a proposal that originates in the native views
    /// rather than in sync materialization, so it answers to the Space access
    /// gate exactly as a semantic command does.
    internal void Commit(ReadOnlySpan<byte> delta, bool nativeValueEdit = false) {
        SessionState previous, next;
        lock (Gate) {
            next = Prepare(delta, nativeValueEdit: nativeValueEdit);
            previous = Accept(next);
        }
        Published(previous, next, followUp: null, SessionTabEvents.None);
    }

    /// The stored parts of the accepted state.
    internal NativeSessionCheckpoint Checkpoint() {
        lock (Gate) return new(session);
    }

    #endregion
}
