namespace CrestCore.Contracts;

/// Shows a tab in a window, switching the window to the tab's Space, and
/// records when the tab was last used, which current-tab cleanup reads. A
/// null tab leaves the Space showing nothing and the window where it is. A
/// Space or tab that is already gone publishes nothing.
public sealed record ShowTab(Guid WindowId, Guid SpaceId, Guid? TabId) : WindowIntent;
