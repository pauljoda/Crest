namespace CrestCore.Domain;

/// What happened to a page's blocked-popup indication, and the state it leaves.
///
/// The page's content bridge coalesces before crossing into native code, and
/// these transitions are the second boundary: even a hostile page posting
/// directly to the bridge cannot stack indications or announcements in one
/// document. The `popups.notice` policy spells an event as its `Name`.
public sealed class BlockedPopupEvent {
    #region Variables

    /// The engine or the page's bridge held back an automatic popup. It needs
    /// the document identifier and the blocked site's origin, and shows one
    /// new indication unless one is already shown.
    public static readonly BlockedPopupEvent Blocked = new(name: "blocked", apply: (state, documentIdentifier, origin) => {
        if (string.IsNullOrEmpty(documentIdentifier) || documentIdentifier.Length > BlockedPopupPageState.MaximumDocumentIdentifierLength
            || origin is null) throw new BrowserRuleException(BrowserRuleCodes.InvalidBlockedPopup);
        return state.Status is not null ? null
            : new(BlockedPopupStatus.Blocked, origin, documentIdentifier, unchecked(state.IndicationRevision + 1));
    });

    /// The person allowed automatic popups for the blocked site.
    public static readonly BlockedPopupEvent PermissionAllowed = new(name: "permission_allowed", apply: (state, _, _) =>
        state.Status == BlockedPopupStatus.Blocked ? state with { Status = BlockedPopupStatus.AllowedAwaitingRetry } : null);

    /// Automatic popups were blocked again before the page retried.
    public static readonly BlockedPopupEvent PermissionBlockedAgain = new(name: "permission_blocked_again", apply: (state, _, _) =>
        state.Status == BlockedPopupStatus.AllowedAwaitingRetry ? state with { Status = BlockedPopupStatus.Blocked } : null);

    /// The page started a new navigation.
    public static readonly BlockedPopupEvent Navigation = new(name: "navigation", apply: (state, _, _) =>
        state.Status is null && state.DocumentIdentifier is null ? null : Cleared(state));

    /// A popup opened after the person allowed it.
    public static readonly BlockedPopupEvent PopupAllowed = new(name: "popup_allowed", apply: (state, _, _) =>
        state.Status == BlockedPopupStatus.AllowedAwaitingRetry ? Cleared(state) : null);

    public static IReadOnlyList<BlockedPopupEvent> All { get; } =
        [Blocked, PermissionAllowed, PermissionBlockedAgain, Navigation, PopupAllowed];

    public string Name { get; }

    private readonly Func<BlockedPopupPageState, string?, SiteOrigin?, BlockedPopupPageState?> apply;

    #endregion

    #region Constructors

    private BlockedPopupEvent(string name, Func<BlockedPopupPageState, string?, SiteOrigin?, BlockedPopupPageState?> apply) {
        Name = name;
        this.apply = apply;
    }

    #endregion

    #region Actions - Lookup

    public static BlockedPopupEvent? Named(string? name) => All.FirstOrDefault(popupEvent => popupEvent.Name == name);

    #endregion

    #region Actions - Popups

    /// The state after this event, or null when it changes nothing.
    public BlockedPopupPageState? Apply(BlockedPopupPageState state, string? documentIdentifier, SiteOrigin? origin) {
        ArgumentNullException.ThrowIfNull(state);
        return apply(state, documentIdentifier, origin);
    }

    private static BlockedPopupPageState Cleared(BlockedPopupPageState state) =>
        state with { Status = null, Origin = null, DocumentIdentifier = null };

    #endregion
}
