namespace CrestCore.Domain;

/// One ordered rule that sends matching external links to a Space.
public sealed record LinkRoute(Guid Id, bool IsEnabled, LinkRouteMatch Match, string Pattern, Guid DestinationSpaceId);
