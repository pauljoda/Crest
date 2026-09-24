namespace CrestCore.Contracts;

/// <summary>
/// A workspace's Spaces changed membership or order. <see cref="Removed"/> Spaces are
/// gone, and each <see cref="Added"/> Space arrives whole and goes after the Spaces
/// that stay. <see cref="Order"/> names every Space in its new order, and is present
/// only when that order differs from the one those two steps leave. A Space that
/// arrives again whole is named in both <see cref="Removed"/> and <see cref="Added"/>.
/// </summary>
public sealed record SpacesChanged(Guid WorkspaceId, IReadOnlyList<SpaceState> Added, IReadOnlyList<Guid> Removed,
    IReadOnlyList<Guid>? Order) : Change;
