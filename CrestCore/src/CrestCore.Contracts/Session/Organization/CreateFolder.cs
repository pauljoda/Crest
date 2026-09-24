namespace CrestCore.Contracts;

/// Creates a folder in a Space's saved or open section, or inside `ParentId`,
/// whose section it shares. A blank title names it "New Folder". The tabs
/// `TabIds` names move into it in the same edit, so a folder nobody asked to
/// see empty is never published, and one whose tabs cannot move is never made.
/// A split member brings its split along, unless `LeavesSplits` takes it out.
public sealed record CreateFolder(Guid WorkspaceId, Guid SpaceId, Guid FolderId, TabPlacement Placement, Guid? ParentId,
    string? Title, BrandColor? Color, string? Symbol, IReadOnlyList<Guid> TabIds, bool LeavesSplits) : SessionIntent(WorkspaceId);
