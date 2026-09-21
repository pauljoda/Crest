using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private readonly NativeSessionAuthority? borrowedSource;
    private readonly Guid borrowedSpace, borrowedProfile;
    private ulong borrowedSourceRevision;
    private bool released;

    // Presentation and organization belong to the temporary workspace. Every
    // other metadata field, including unknown compatible fields, follows its owner.
    private static readonly string[] LocalBorrowedFields =
        ["selectedTabID", "splitGroups", "isSavedTabsExpanded", "savedTabsExpansionModifiedAt"];

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
            var fields = original.Metadata.DeepClone().AsObject();
            fields["selectedTabID"] = null; fields["splitGroups"] = new JsonArray();
            var empty = Sections.ToDictionary(s => s, _ => (IReadOnlyList<JsonNode>)Array.Empty<JsonNode>());
            var metadata = new JsonObject {
                ["selectedSpaceID"] = fields["id"]!.DeepClone(),
                ["defaultSpaceID"] = fields["id"]!.DeepClone()
            };
            return new(new(metadata, [new(fields, empty)]), this, spaceId, profileId);
        }
    }

    private SpaceDocument RequireBorrowedSource() {
        var source = borrowedSource ?? throw new BrowserRuleException(BrowserRuleCodes.NotBorrowedWorkspace);
        var original = source.document.Spaces.SingleOrDefault(s => Id(s.Metadata["id"]) == borrowedSpace);
        BorrowedProfilePolicy.RequireSource(new(borrowedSpace), new(borrowedProfile),
            new(original is null ? Guid.Empty : Id(original.Metadata["id"])),
            new(original is null ? Guid.Empty : Id(original.Metadata["profile"]!["id"])),
            !source.released && PendingDeletion(source.document.Metadata, borrowedSpace) is null);
        return original!;
    }

    private static JsonObject BorrowedMetadata(SpaceDocument original, SpaceDocument local) {
        var result = original.Metadata.DeepClone().AsObject();
        foreach (var field in LocalBorrowedFields) {
            result.Remove(field);
            if (local.Metadata.TryGetPropertyValue(field, out var value)) result[field] = value?.DeepClone();
        }
        return result;
    }

    private void ValidateBorrowedDocument(SessionDocument value) {
        if (borrowedSource is null) return;
        var original = RequireBorrowedSource();
        if (value.Spaces.Count != 1 || !JsonNode.DeepEquals(
            Fields(value.Spaces[0].Metadata, LocalBorrowedFields), Fields(original.Metadata, LocalBorrowedFields)))
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
            var next = new SessionDocument(document.Metadata,
                [new(BorrowedMetadata(original, local), local.Sections)]);
            Validate(next);
            return new(this, expected, next, MetadataProjection(next));
        }
    }

    private static byte[] MetadataProjection(SessionDocument value) {
        var projection = value.Metadata.DeepClone().AsObject();
        projection["spaces"] = new JsonArray(value.Spaces.Select(s => {
            var fields = s.Metadata.DeepClone().AsObject();
            foreach (var section in Sections) fields[section] = new JsonArray();
            return (JsonNode)fields;
        }).ToArray());
        var output = Encoding.UTF8.GetBytes(new JsonObject { ["session"] = projection }.ToJsonString());
        if (output.Length > NativeSessionEditor.MaximumBytes) throw new BrowserRuleException(BrowserRuleCodes.SessionEditLimit);
        return output;
    }

    public void Release() { lock (Gate) released = true; }

    #endregion
}
