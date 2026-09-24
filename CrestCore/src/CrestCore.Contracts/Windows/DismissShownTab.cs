namespace CrestCore.Contracts;

/// Stops a window showing a tab the session keeps, such as a saved page it
/// closes without closing the tab: the window shows the tab it showed before
/// in that Space, recording its use, or nothing. A window that no longer
/// shows the tab publishes nothing.
public sealed record DismissShownTab(Guid WindowId, Guid SpaceId, Guid TabId) : WindowIntent;
