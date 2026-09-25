namespace CrestCore.Contracts;

/// What a window's numbered commands choose from: the Space it shows, the tab
/// each stop of that Space's sidebar leads to, in order, and the Spaces it may
/// show, in order.
public sealed record NumberedChoices(Guid ShownSpaceId, IReadOnlyList<Guid> Tabs, IReadOnlyList<Guid> Spaces);
