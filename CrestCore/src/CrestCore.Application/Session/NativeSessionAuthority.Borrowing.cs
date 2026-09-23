using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private readonly NativeSessionAuthority? borrowedSource;
    private readonly Guid borrowedSpace, borrowedProfile;
    private ulong borrowedSourceRevision;
    private bool released;

    // Organization belongs to the temporary workspace: its records, its split
    // metadata and whether its saved tabs are expanded. Every other setting
    // follows its owner.
    private static readonly string[] LocalBorrowedFields = ["isSavedTabsExpanded", "savedTabsExpansionModifiedAt"];

    internal ulong? BorrowedRevision => borrowedSource is null ? null : borrowedSource.Revision;

    #endregion

    #region Constructors

    private NativeSessionAuthority(SessionDocument initial, NativeSessionAuthority source, Guid space, Guid profile) {
        document = initial; workspaceKind = BrowserWorkspaceKind.Temporary;
        privateBrowsing = source.privateBrowsing; Engine = source.Engine; access = source.access;
        borrowedSource = source; borrowedSpace = space; borrowedProfile = profile;
        borrowedSourceRevision = source.Revision;
        Validate(document);
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
            var metadata = new JsonObject { ["defaultSpaceID"] = StoredSessionCodec.WrappedIdentity(original.Id) };
            var borrowed = new SpaceDocument(original.Metadata.DeepClone().AsObject(), [], [], [], [], []);
            return new(new(metadata, [borrowed]), this, spaceId, profileId);
        }
    }

    private SpaceDocument RequireBorrowedSource() {
        var source = borrowedSource ?? throw new BrowserRuleException(BrowserRuleCodes.NotBorrowedWorkspace);
        var original = source.document.Spaces.SingleOrDefault(s => s.Id == borrowedSpace);
        BorrowedProfilePolicy.RequireSource(borrowedSpace, borrowedProfile,
            original?.Id ?? Guid.Empty, original?.ProfileId ?? Guid.Empty,
            !source.released && PendingDeletion(source.document.Metadata, borrowedSpace) is null);
        return original!;
    }

    /// The borrowed Space with its owner's current settings and its own organization.
    private static SpaceDocument BorrowedSpace(SpaceDocument original, SpaceDocument local) {
        var result = original.Metadata.DeepClone().AsObject();
        foreach (var field in LocalBorrowedFields) {
            result.Remove(field);
            if (local.Metadata.TryGetPropertyValue(field, out var value)) result[field] = value?.DeepClone();
        }
        return local with { Metadata = result };
    }

    private void ValidateBorrowedDocument(SessionDocument value) {
        if (borrowedSource is null) return;
        var original = RequireBorrowedSource();
        if (value.Spaces.Count != 1 || !JsonNode.DeepEquals(
            StoredSessionCodec.Fields(value.Spaces[0].Metadata, LocalBorrowedFields),
            StoredSessionCodec.Fields(original.Metadata, LocalBorrowedFields)))
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
            var original = RequireBorrowedSource(); var local = document.Spaces.Single();
            var next = new SessionDocument(document.Metadata, [BorrowedSpace(original, local)]);
            Validate(next);
            return new(this, expected, next, MetadataProjection(next));
        }
    }

    private static byte[] MetadataProjection(SessionDocument value) => Output(new JsonObject {
        ["session"] = StoredSessionCodec.Encode(value with { Spaces = value.Spaces.Select(Settings).ToArray() })
    });

    public void Release() { lock (Gate) released = true; }

    #endregion
}
