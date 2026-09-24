namespace CrestCore.Contracts;

/// Renames a Space and sets its symbol and accent. A blank name reads as
/// "Untitled Space", and a blank symbol as the default one.
public sealed record SetSpaceIdentity(Guid WorkspaceId, Guid SpaceId, string Name, string Symbol, SpaceAccent Accent)
    : SessionIntent(WorkspaceId);
