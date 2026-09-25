namespace CrestCore.Contracts;

/// Where each numbered command leads in a window: to the stops of the Space it
/// shows, in the order its sidebar shows them (see `SidebarOutline.Stops`), and
/// to the Spaces it may show, in the session's order, which leaves out one
/// being deleted.
public sealed record NumberedSelections(Guid WindowId) : Query<NumberedSelectionList>;
