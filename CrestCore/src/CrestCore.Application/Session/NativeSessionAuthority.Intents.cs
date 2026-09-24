using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// What one session intent changes: the next session, how it stages, what
    /// the window that issued it shows next, what it did that the two states
    /// cannot tell, and the sweep it records.
    private sealed record SessionEdit(SessionState Next, SyncStaging Staging, WindowFollowUp? FollowUp = null,
        SessionTabEvents? Events = null, SweepMark? Sweep = null);

    #endregion

    #region Actions - Intents

    /// Runs one session intent at `now`, drawing new identities from `ids`,
    /// and commits what it changed, which the device publishes. An intent that
    /// changes nothing commits nothing. Throws `Rejected` naming the rule that
    /// refused it.
    internal void Handle(SessionIntent intent, DateTimeOffset now, IIdSource ids) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        NativeSessionCommand command;
        lock (Gate) {
            var edit = Edit(intent, Stamp(now), ids);
            if (edit is null) return;
            if (edit.Sweep is { } sweep) lastSweep = sweep;
            if (edit.Next.Equals(session)) return;
            command = new NativeSessionCommand(this, session, edit.Next, [], followUp: edit.FollowUp, events: edit.Events)
                .StagedAs(edit.Staging);
        }
        Commit(command);
    }

    /// Throws the `Rejected` that would refuse `intent` at `now`, and changes
    /// nothing. New identities come from `ids`, and are never used.
    internal void Check(SessionIntent intent, DateTimeOffset now, IIdSource ids) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        lock (Gate) _ = Edit(intent, Stamp(now), ids);
    }

    /// The edit an intent makes to the accepted session, validated, or null
    /// for a sweep the last one makes unnecessary. The caller holds the gate.
    private SessionEdit? Edit(SessionIntent intent, DateTimeOffset now, IIdSource ids) {
        var basis = IntentBasis();
        var edit = intent switch {
            ClearHistory clear => ClearingHistory(basis, clear),
            RemoveHistoryAddress removal => RemovingHistory(basis, removal),
            RemoveHistoryRange removal => RemovingHistory(basis, removal),
            SweepExpiredRecords => Sweeping(basis, now),
            CleanUpCurrentTabs cleanup => CleaningUp(basis, cleanup, now),
            RestoreArchivedTab restore => Restoring(basis, restore, now),
            CreateFolder creation => CreatingFolder(basis, creation, now),
            RenameFolder rename => RenamingFolder(basis, rename),
            CollapseFolder collapse => CollapsingFolder(basis, collapse, now),
            SetFolderColor color => ColoringFolder(basis, color),
            SetFolderSymbol symbol => SymbolizingFolder(basis, symbol),
            MoveFolder move => MovingFolder(basis, move, now),
            DeleteFolder deletion => DeletingFolder(basis, deletion, now),
            FileTabs filing => Filing(basis, filing, now),
            JoinSplit join => JoiningSplit(basis, join, now, ids),
            OpenLinkInSplit link => OpeningLinkInSplit(basis, link, now, ids),
            LeaveSplit leave => LeavingSplit(basis, leave, now),
            MoveSplitMember move => MovingSplitMember(basis, move, now),
            StepSplitMember step => SteppingSplitMember(basis, step, now),
            DissolveSplit dissolve => DissolvingSplit(basis, dissolve, now),
            MoveSplit move => MovingSplit(basis, move, now),
            NameSplit name => NamingSplit(basis, name, now),
            SetSplitIcon icon => SettingSplitIcon(basis, icon, now),
            TintSplit tint => TintingSplit(basis, tint, now),
            _ => throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "The session does not handle this intent.")
        };
        if (edit is null) return null;
        Validate(edit.Next);
        ValidateBorrowedSession(edit.Next);
        return edit;
    }

    /// The accepted session an intent edits. A borrowed Space takes its
    /// owner's current settings, as a refresh would, since an intent proposes
    /// no settings of its own.
    private SessionState IntentBasis() {
        if (released) throw new Rejected(new UnknownWorkspace(workspaceId));
        if (replacement is not null) throw new Rejected(new WorkspaceBusy(workspaceId));
        if (borrowedSource is not { } source) return session;
        var original = source.session.Spaces.SingleOrDefault(space => space.Id == borrowedSpace);
        if (source.released || original is null || original.ProfileId != borrowedProfile)
            throw new Rejected(new UnknownSpace(borrowedSpace));
        if (PendingDeletion(source.session, borrowedSpace) is not null) throw new Rejected(new SpaceBeingDeleted(borrowedSpace));
        var local = session.Spaces.Single();
        var refreshed = BorrowedSpace(original, local);
        return refreshed == local ? session : session with { Spaces = [refreshed] };
    }

    /// The Space an intent edits: one `basis` holds that is not being deleted,
    /// and, unless the edit only maintains it, one this process may read.
    private SpaceState Editable(SessionState basis, Guid spaceId, bool maintains = false) {
        var space = basis.Spaces.FirstOrDefault(candidate => candidate.Id == spaceId) ?? throw new Rejected(new UnknownSpace(spaceId));
        if (PendingDeletion(basis, spaceId) is not null) throw new Rejected(new SpaceBeingDeleted(spaceId));
        if (!maintains && IsLockedUnderGate(space)) throw new Rejected(new SpaceLocked(spaceId));
        return space;
    }

    /// The Spaces an intent that names none edits: every one `basis` holds that
    /// is not being deleted, and, unless the edit only maintains them, that
    /// this process may read.
    private IEnumerable<SpaceState> EditableSpaces(SessionState basis, bool maintains = false) =>
        basis.Spaces.Where(space => PendingDeletion(basis, space.Id) is null && (maintains || !IsLockedUnderGate(space)));

    /// The window that issued an intent, as it is now, or null when it is not
    /// open over this workspace.
    private Window? IssuingWindow(Guid windowId) => device?.Snapshot(workspaceId, windowId);

    /// `now` as the session stores it, so the next load reads the same value.
    private static DateTimeOffset Stamp(DateTimeOffset now) => StoredSessionCodec.Date(StoredSessionCodec.Seconds(now));

    #endregion
}
