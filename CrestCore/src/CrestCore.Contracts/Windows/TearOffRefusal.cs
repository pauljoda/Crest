namespace CrestCore.Contracts;

/// Why a dragged tab may not leave its window.
public enum TearOffRefusal {
    /// The window no longer shows the Space the drag started in, with the
    /// profile it had, or the Space is being deleted.
    SpaceChanged,
    /// The Space is locked.
    SpaceLocked,
    /// The Space no longer holds the tab.
    TabGone,
    /// The drag carries more than the one tab.
    SeveralTabs
}
