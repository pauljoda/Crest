using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// What one session intent changes: the next session, how it stages (null
    /// for an edit no journal ever reads), what the window that issued it
    /// shows next, what it did that the two states cannot tell, the sweep it
    /// records, and the Quick Window or Peek page it kept or archived.
    private sealed record SessionEdit(SessionState Next, SyncStaging? Staging, WindowFollowUp? FollowUp = null,
        SessionTabEvents? Events = null, SweepMark? Sweep = null, Guid? Completes = null);

    #endregion

    #region Actions - Intents

    /// Runs one session intent at `now`, drawing new identities from `ids`
    /// and reading the Quick Window and Peek pages an intent names from
    /// `pages`, and commits what it changed, which the device publishes. An
    /// intent that changes nothing commits nothing, and publishes only what it
    /// did that the session cannot tell, such as the image a tab now wears,
    /// and what its window shows next, such as the tab it returns to after
    /// putting a saved tab's page away. Throws `Rejected` naming the rule that
    /// refused it, or `SaveFailed` for an edit saved before it returns whose
    /// save failed, which changed nothing.
    internal void Handle(SessionIntent intent, DateTimeOffset now, IIdSource ids, Func<Guid, TransientPage?>? pages = null) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        NativeSessionCommand? command = null;
        (SessionState State, SessionTabEvents Events, WindowFollowUp? FollowUp)? unchanged = null;
        lock (Gate) {
            var edit = Edit(intent, Stamp(now), ids, pages);
            if (edit is null) return;
            if (edit.Sweep is { } sweep) lastSweep = sweep;
            if (!edit.Next.Equals(session))
                command = new NativeSessionCommand(this, session, edit.Next, [], transientCompletion: edit.Completes,
                    followUp: edit.FollowUp, events: edit.Events).StagedAs(edit.Staging);
            else if (edit.Events is not null || edit.FollowUp is not null)
                unchanged = (session, edit.Events ?? SessionTabEvents.None, edit.FollowUp);
        }
        if (command is null) {
            if (unchanged is { } kept) Published(kept.State, kept.State, kept.FollowUp, kept.Events);
            return;
        }
        try {
            Commit(command);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
    }

    /// Throws the `Rejected` that would refuse `intent` at `now`, and changes
    /// nothing. New identities come from `ids`, and are never used.
    internal void Check(SessionIntent intent, DateTimeOffset now, IIdSource ids, Func<Guid, TransientPage?>? pages = null) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        lock (Gate) _ = Edit(intent, Stamp(now), ids, pages);
    }

    /// The edit an intent makes to the accepted session, validated, or null
    /// for a sweep the last one makes unnecessary. The caller holds the gate.
    private SessionEdit? Edit(SessionIntent intent, DateTimeOffset now, IIdSource ids, Func<Guid, TransientPage?>? pages) {
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
            OpenTab opening => OpeningTab(basis, opening, now),
            CloseTab closing => ClosingTab(basis, closing, now),
            DeleteTab deletion => DeletingTab(basis, deletion, now),
            ClearCurrentTabs clearing => ClearingCurrentTabs(basis, clearing, now),
            DuplicateTab copy => DuplicatingTab(basis, copy, now, ids),
            MoveTab move => MovingTab(basis, move, now),
            PromoteTransientPage promotion => PromotingTransientPage(basis, promotion, now, ids, pages),
            ArchiveTransientPage archive => ArchivingTransientPage(basis, archive, now, ids, pages),
            NavigateTab navigation => NavigatingTab(basis, navigation),
            RenameTab rename => RenamingTab(basis, rename, now),
            ChooseTabIcon icon => ChoosingTabIcon(basis, icon),
            ReplaceSavedAddress adoption => ReplacingSavedAddress(basis, adoption),
            ReturnToSavedAddress returning => ReturningToSavedAddress(basis, returning),
            KeepPageLoaded residency => KeepingPageLoaded(basis, residency),
            CreateSpace creation => CreatingSpace(basis, creation, now, ids),
            SetSpaceIdentity identity => SettingIdentity(basis, identity),
            SetSpaceBranding branding => SettingBranding(basis, branding),
            SetCredentialPreferences credentials => SettingCredentials(basis, credentials),
            SetSpaceAccess access => SettingAccess(basis, access),
            SetDefaultSpace choice => SettingDefault(basis, choice),
            ReorderSpaces order => Reordering(basis, order),
            ExpandSavedTabs expansion => ExpandingSavedTabs(basis, expansion, now),
            BeginDeletingSpace deletion => BeginningDeletion(basis, deletion),
            FinishDeletingSpace deletion => FinishingDeletion(basis, deletion),
            ResetPrivateBrowsing reset => ResettingPrivateBrowsing(basis, reset, now, ids),
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
