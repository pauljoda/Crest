namespace CrestCore.Domain;

/// Which tab a window shows for a Space after repair.
public enum WindowTabSelection {
    /// Keep the tab the window already chose.
    Window,

    /// Fall back to the Space's first tab.
    First,

    /// Show no tab: the window deliberately left this Space empty, or it has none.
    None
}
