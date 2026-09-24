namespace CrestCore.Contracts;

/// One page this device hosts: the workspace and Space it belongs to, the tab
/// that owns it, the engine that hosts it, where it stands there and its live
/// state. A page without a tab belongs to a transient request, a Quick Window
/// or a Peek.
[Observed]
public sealed record PageState(Guid Id, Guid WorkspaceId, Guid SpaceId, Guid? TabId, EngineKind Engine, PagePhase Phase,
    PageLiveState Live);
