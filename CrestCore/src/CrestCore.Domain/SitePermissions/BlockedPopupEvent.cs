namespace CrestCore.Domain;

/// What happened to a page's blocked-popup indication.
public enum BlockedPopupEvent {
    /// The engine or the page's bridge held back an automatic popup.
    Blocked,
    /// The person allowed automatic popups for the blocked site.
    PermissionAllowed,
    /// Automatic popups were blocked again before the page retried.
    PermissionBlockedAgain,
    /// The page started a new navigation.
    Navigation,
    /// A popup opened after the person allowed it.
    PopupAllowed,
}
