using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private readonly NativeSessionAuthority? borrowedSource;
    private readonly Guid borrowedSpace, borrowedProfile;
    private bool released;

    #endregion

    #region Constructors

    private NativeSessionAuthority(SessionState initial, NativeSessionAuthority source, Guid space, Guid profile) {
        session = initial; workspaceKind = WorkspaceKind.Borrowed;
        privateBrowsing = source.privateBrowsing; access = source.access;
        borrowedSource = source; borrowedSpace = space; borrowedProfile = profile;
        Validate(session);
    }

    #endregion

    #region Actions - Borrowing

    public NativeSessionAuthority CreateBorrowed(Guid spaceId, Guid profileId) {
        lock (Gate) {
            RequireWritable();
            SpaceOrganizationPolicy.RequireOwnedProfiles(workspaceKind);
            RequireAccessible(spaceId);
            var original = BorrowableSpace(spaceId, profileId);
            var borrowed = original with { Folders = [], Tabs = [], SplitGroups = [], ArchivedTabs = [], History = [] };
            return new(new([borrowed], original.Id, null, [], null), this, spaceId, profileId);
        }
    }

    /// The Space a workspace borrows, which must be the one `spaceId` names
    /// with the profile `profileId` names and not being deleted.
    private SpaceState BorrowableSpace(Guid spaceId, Guid profileId) {
        if (PendingDeletion(session, spaceId) is not null) throw new BrowserRuleException(BrowserRuleCodes.SpaceDeletionInProgress);
        var space = session.Spaces.SingleOrDefault(s => s.Id == spaceId)
            ?? throw new BrowserRuleException(BrowserRuleCodes.UnknownSpace);
        if (space.ProfileId != profileId) throw new BrowserRuleException(BrowserRuleCodes.WrongProfileIdentity);
        return space;
    }

    private SpaceState RequireBorrowedSource() {
        var source = borrowedSource ?? throw new BrowserRuleException(BrowserRuleCodes.NotBorrowedWorkspace);
        var original = source.session.Spaces.SingleOrDefault(s => s.Id == borrowedSpace);
        BorrowedProfilePolicy.RequireSource(borrowedSpace, borrowedProfile,
            original?.Id ?? Guid.Empty, original?.ProfileId ?? Guid.Empty,
            !source.released && PendingDeletion(source.session, borrowedSpace) is null);
        return original!;
    }

    /// The borrowed Space with its owner's current settings and its own
    /// organization. Organization belongs to the temporary workspace: its
    /// records, its split metadata and whether its saved tabs are expanded.
    /// Every other setting follows its owner.
    private static SpaceState BorrowedSpace(SpaceState original, SpaceState local) => original with {
        Folders = local.Folders,
        Tabs = local.Tabs,
        SplitGroups = local.SplitGroups,
        ArchivedTabs = local.ArchivedTabs,
        History = local.History,
        Settings = original.Settings with {
            IsSavedTabsExpanded = local.Settings.IsSavedTabsExpanded,
            SavedTabsExpansionModifiedAt = local.Settings.SavedTabsExpansionModifiedAt
        }
    };

    private void ValidateBorrowedSession(SessionState value) {
        if (borrowedSource is null) return;
        var original = RequireBorrowedSource();
        if (value.Spaces.Count != 1 || BorrowedSpace(original, value.Spaces[0]) != value.Spaces[0])
            throw new BrowserRuleException(BrowserRuleCodes.BorrowedProfileRequiresOwner);
    }

    /// Throws unless `value`, a state of a borrowed session, shows its Space
    /// with the settings its owner holds now; a refresh brings it up to date.
    /// Any other session always passes.
    internal void RequireCurrentBorrowedPolicy(SessionState value) {
        if (borrowedSource is null) return;
        var original = RequireBorrowedSource();
        if (value.Spaces.Count != 1 || BorrowedSpace(original, value.Spaces[0]) != value.Spaces[0])
            throw new BrowserRuleException(BrowserRuleCodes.StaleBorrowedSource);
    }

    /// A command that brings the borrowed Space's settings up to date with its
    /// owner, and changes nothing when they already are.
    public NativeSessionCommand PrepareBorrowedRefresh() {
        lock (Gate) {
            RequireWritable(requireCurrentBorrowedPolicy: false);
            var original = RequireBorrowedSource(); var local = session.Spaces.Single();
            var refreshed = BorrowedSpace(original, local);
            var next = refreshed == local ? session : session with { Spaces = [refreshed] };
            Validate(next);
            return new(this, session, next, []);
        }
    }

    /// Takes no more edits, and the windows over this session close with it.
    public void Release() {
        Device? target;
        Guid workspace;
        lock (Gate) {
            released = true;
            target = device;
            workspace = workspaceId;
        }
        target?.Detach(workspace);
    }

    #endregion
}
