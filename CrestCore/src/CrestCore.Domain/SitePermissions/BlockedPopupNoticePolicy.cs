namespace CrestCore.Domain;

/// The blocked-popup notice rules. The page's content bridge coalesces
/// before crossing into native code, and these transitions are the second
/// boundary: even a hostile page posting directly to the bridge cannot stack
/// indications or announcements in one document.
public static class BlockedPopupNoticePolicy {
    #region Actions - Popups

    /// Whether a saved decision lets a site open windows without a user
    /// gesture. A click-activated popup never needs this permission.
    public static bool AllowsAutomaticPopups(SitePermissionDecision decision) => SitePermissionDecisionPolicy.Grants(decision);

    /// The state after one event, or null when the event changes nothing.
    /// `Blocked` needs the document identifier and the blocked site's origin.
    public static BlockedPopupPageState? Apply(BlockedPopupPageState state, BlockedPopupEvent popupEvent,
        string? documentIdentifier, SiteOrigin? origin) {
        ArgumentNullException.ThrowIfNull(state);
        switch (popupEvent) {
            case BlockedPopupEvent.Blocked:
                if (string.IsNullOrEmpty(documentIdentifier) || documentIdentifier.Length > BlockedPopupPageState.MaximumDocumentIdentifierLength
                    || origin is null) throw new BrowserRuleException(BrowserRuleCodes.InvalidBlockedPopup);
                if (state.Status is not null) return null;
                return new(BlockedPopupStatus.Blocked, origin, documentIdentifier, unchecked(state.IndicationRevision + 1));
            case BlockedPopupEvent.PermissionAllowed:
                return state.Status == BlockedPopupStatus.Blocked ? state with { Status = BlockedPopupStatus.AllowedAwaitingRetry } : null;
            case BlockedPopupEvent.PermissionBlockedAgain:
                return state.Status == BlockedPopupStatus.AllowedAwaitingRetry ? state with { Status = BlockedPopupStatus.Blocked } : null;
            case BlockedPopupEvent.Navigation:
                return state.Status is null && state.DocumentIdentifier is null ? null : Cleared(state);
            default:
                return state.Status == BlockedPopupStatus.AllowedAwaitingRetry ? Cleared(state) : null;
        }
    }

    private static BlockedPopupPageState Cleared(BlockedPopupPageState state) =>
        state with { Status = null, Origin = null, DocumentIdentifier = null };

    #endregion
}
