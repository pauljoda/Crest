namespace CrestCore.Contracts;

/// Where a lift of `Selection` in a window's sidebar may drop, answered once as
/// the lift begins: each `SidebarDrop` it could commit, with the rule that
/// would refuse it now. A drop may still be refused when it lands, since the
/// session can change while the lift is held; its commit decides.
public sealed record DropTargets(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : Query<DropTargetList>;
