using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The one route field a settings edit changes. Exactly one value is set.
public sealed record LinkRouteField(bool? IsEnabled = null, LinkRouteMatch? Match = null, string? Pattern = null,
    Guid? DestinationSpaceId = null);
