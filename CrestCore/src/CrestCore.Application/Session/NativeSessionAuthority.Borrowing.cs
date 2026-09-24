using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private readonly NativeSessionAuthority? borrowedSource;
    private readonly Guid borrowedSpace, borrowedProfile;
    private ulong borrowedSourceRevision;
    private bool released;

    internal ulong? BorrowedRevision => borrowedSource is null ? null : borrowedSource.Revision;

    #endregion

    #region Constructors

    private NativeSessionAuthority(SessionState initial, NativeSessionAuthority source, Guid space, Guid profile) {
        session = initial; workspaceKind = BrowserWorkspaceKind.Temporary;
        privateBrowsing = source.privateBrowsing; Engine = source.Engine; access = source.access;
        borrowedSource = source; borrowedSpace = space; borrowedProfile = profile;
        borrowedSourceRevision = source.Revision;
        Validate(session);
    }

    #endregion

    #region Actions - Borrowing

    public NativeSessionAuthority CreateBorrowed(ulong expected, Guid spaceId, Guid profileId) {
        lock (Gate) {
            RequireWritable();
            SpaceOrganizationPolicy.RequireOwnedProfiles(workspaceKind);
            if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
            RequireAccessible(spaceId);
            var original = TransferSpace(spaceId, profileId);
            var borrowed = original with { Folders = [], Tabs = [], SplitGroups = [], ArchivedTabs = [], History = [] };
            return new(new([borrowed], original.Id, null, [], null), this, spaceId, profileId);
        }
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
        IsSavedTabsExpanded = local.IsSavedTabsExpanded,
        SavedTabsExpansionModifiedAt = local.SavedTabsExpansionModifiedAt
    };

    private void ValidateBorrowedSession(SessionState value) {
        if (borrowedSource is null) return;
        var original = RequireBorrowedSource();
        if (value.Spaces.Count != 1 || BorrowedSpace(original, value.Spaces[0]) != value.Spaces[0])
            throw new BrowserRuleException(BrowserRuleCodes.BorrowedProfileRequiresOwner);
    }

    internal void RequireBorrowedRevision(ulong? expected) {
        if (borrowedSource is null) return;
        _ = RequireBorrowedSource();
        if (expected != borrowedSource.Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleBorrowedSource);
    }

    public NativeSessionCommand PrepareBorrowedRefresh(ulong expected) {
        lock (Gate) {
            RequireWritable(requireCurrentBorrowedPolicy: false);
            if (expected != Revision) throw new BrowserRuleException(BrowserRuleCodes.StaleSessionRevision);
            var original = RequireBorrowedSource(); var local = session.Spaces.Single();
            var next = session with { Spaces = [BorrowedSpace(original, local)] };
            Validate(next);
            return new(this, expected, next, SettingsProjection(next));
        }
    }

    private static byte[] SettingsProjection(SessionState value) => Output(new JsonObject {
        ["session"] = StoredSessionCodec.Encode(value with { Spaces = value.Spaces.Select(Settings).ToArray() })
    });

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
