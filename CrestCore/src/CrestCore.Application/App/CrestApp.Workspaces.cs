using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Static Variables

    /// How deep a seed's stored document may nest, as the stored format reads it.
    private static readonly JsonDocumentOptions SeedDocument = new() { MaxDepth = 64 };

    #endregion

    #region Actions - Workspaces

    /// Runs one workspace intent. What it changes joins the pending batch in
    /// the order it happened: a closing workspace's pages, then its windows,
    /// then that it closed; an opening workspace whole, then the tabs its
    /// repair gave a new identity. The caller holds the lock.
    private void Handle(WorkspaceIntent intent) {
        switch (intent) {
            case OpenWorkspace opening: Open(opening); break;
            case BorrowSpace borrowing: Borrow(borrowing); break;
            case CloseWorkspace closing: Close(closing.WorkspaceId); break;
            default: throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "No area handles this workspace intent.");
        }
    }

    private void Open(OpenWorkspace intent) {
        if (!intent.Kind.OpensDirectly) throw new Rejected(new BorrowedWorkspaceRequiresSpace(intent.Kind));
        if (intent.Seed is { } seed) device.Attach(new NativeSessionAuthority(intent.Kind, Seeded(seed)), ids.Next());
        else if (intent.Kind.KeepsFile) OpenStored();
        else device.Attach(new NativeSessionAuthority(intent.Kind, Template(intent.Kind)), ids.Next());
    }

    /// Opens the session this core keeps in its file, then attaches the sync
    /// component it stages into, so the transport hears the launch stage. A
    /// session already open publishes itself again.
    private void OpenStored() {
        if (storedSession is not { } session) throw new Rejected(new NoStoredSession());
        if (device.Identity(session) is { } open) {
            Announce(new WorkspaceOpened(open, session.Kind, session.Current));
            return;
        }
        if (session.IsReleased) throw new Rejected(new StoredSessionClosed());
        var workspaceId = ids.Next();
        device.AttachPersistent(session, storedSelection, workspaceId);
        session.AttachSync(storedSync!);
        foreach (var (source, copy) in repairedCopies) Announce(new TabCopied(workspaceId, source, copy));
    }

    /// A seed in the stored format, as a session a workspace can hold. Throws
    /// `Rejected` with `InvalidSeed` naming the first rule it breaks.
    private static SessionState Seeded(byte[] seed) {
        SessionState session;
        try {
            session = StoredSessionCodec.DecodeSession(JsonNode.Parse(seed, documentOptions: SeedDocument));
        } catch (Exception error) when (StoredSession.IsUndecodable(error)) {
            throw new Rejected(new InvalidSeed(SeedFlaw.Unreadable));
        }
        return NativeSessionAuthority.Flaw(session) is { } flaw ? throw new Rejected(new InvalidSeed(flaw)) : session;
    }

    /// The session a workspace of `kind` starts with when it keeps no file and
    /// has no seed: one Space of its kind's template, showing a Start Page
    /// stamped as the session stores the time.
    private SessionState Template(WorkspaceKind kind) {
        var now = StoredSessionCodec.Date(StoredSessionCodec.Seconds(clock.Now));
        var space = SpaceTemplate.For(kind.IsPrivate).Make(ids.Next(), ids.Next(), ids.Next(), number: 1, now);
        return new([space], DefaultSpaceId: null, DisposableSeedMarker: null, SpaceDeletions: [], AppPreferences: null);
    }

    private void Borrow(BorrowSpace intent) {
        var owner = device.Workspace(intent.WorkspaceId);
        device.Attach(owner.Borrow(intent.SpaceId, intent.ProfileId), ids.Next());
    }

    /// Closes a workspace and, first, every workspace that borrows from it:
    /// its session takes no edits, its pages go and their engines close what
    /// they hold, then its windows close, keeping their saved records, and its
    /// sync stops once its queued stages ran. The caller holds the lock.
    private void Close(Guid workspaceId) {
        if (device.Attached(workspaceId) is not { } session) return;
        foreach (var borrower in device.Borrowers(session)) Close(borrower);
        session.Close();
        var dropped = new ChangeFeed();
        pages.Drop(workspaceId, dropped, Issue);
        foreach (var change in dropped.Published) Announce(change);
        device.Detach(workspaceId);
        if (ReferenceEquals(session, storedSession)) storedSync?.Stop();
    }

    /// A borrowed workspace whose owner no longer lends its Space closes. An
    /// owner reaches this while an intent holds the lock, and then the intent
    /// delivers what the close issued.
    ///
    /// TRANSITIONAL until S5.8c: the JSON command and replacement paths commit
    /// an owner's state without the lock, so the close takes it itself and
    /// delivers its engine commands afterwards. Once those paths are intents,
    /// the lock is always held here.
    private void CloseOrphan(Guid workspaceId) {
        var nested = gate.IsHeldByCurrentThread;
        lock (gate) Close(workspaceId);
        if (nested) return;
        WakeIfOwed();
        Deliver();
    }

    /// The workspace `workspaceId` names, for the paths that still reach a
    /// session outside an intent.
    internal NativeSessionAuthority Workspace(Guid workspaceId) => device.Workspace(workspaceId);

    #endregion

    #region Actions - Replacement

    /// TRANSITIONAL until slice 8a (typed sync): replaces the workspace's session with the
    /// edits `delta` names and saves the result, with a sync transaction's
    /// journal when one is given, before publishing it.
    public void ReplaceDurably(Guid workspaceId, ReadOnlySpan<byte> delta, NativeSyncTransaction? transaction) =>
        device.Workspace(workspaceId).ReplaceDurably(delta, transaction);

    #endregion
}
