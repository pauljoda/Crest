namespace CrestCore.Contracts;

/// Moves a tab `Offset` members along its split. A step past either end
/// changes nothing.
public sealed record StepSplitMember(Guid WorkspaceId, Guid SpaceId, Guid TabId, int Offset) : SessionIntent(WorkspaceId);
