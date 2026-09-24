namespace CrestCore.Contracts;

/// Sets how a Space's sidebar and icon look, within the ranges every device
/// draws.
public sealed record SetSpaceBranding(Guid WorkspaceId, Guid SpaceId, SpaceBranding Branding) : SessionIntent(WorkspaceId);
