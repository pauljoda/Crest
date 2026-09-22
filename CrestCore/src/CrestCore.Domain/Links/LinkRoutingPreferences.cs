namespace CrestCore.Domain;

/// The link preferences routing reads. `RememberedSpaceId` is the Space
/// remembered for the link's site, already looked up by its `Site` key.
public sealed record LinkRoutingPreferences(IReadOnlyList<LinkRoute> Routes, ExternalLinkDestination Destination,
    Guid? ChosenSpaceId, bool RemembersSpaceBySite, Guid? RememberedSpaceId);
