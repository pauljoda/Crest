namespace CrestCore.Contracts;

/// One manual-setup draft: the Space `SpaceId` of the setup's Spaces, whether
/// it is a new Space, and the name and look it takes.
public sealed record SetupSpace(Guid SpaceId, bool IsNew, SpaceCustomization Customization);
