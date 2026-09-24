namespace CrestCore.Contracts;

/// Shows a Space in a window, on the tab the window last showed there while
/// it still exists, or else on the Space's fallback tab. A Space that is gone
/// or being deleted publishes nothing.
public sealed record ShowSpace(Guid WindowId, Guid SpaceId) : WindowIntent;
