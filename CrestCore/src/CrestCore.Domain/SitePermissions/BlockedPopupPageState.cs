namespace CrestCore.Domain;

/// Document-scoped blocked-popup state for one page. `Status` and `Origin`
/// are both null when no indication is shown. `IndicationRevision` advances
/// once per new indication so the page announces it once.
public sealed record BlockedPopupPageState(BlockedPopupStatus? Status, SiteOrigin? Origin, string? DocumentIdentifier,
    int IndicationRevision) {
    #region Variables

    public const int MaximumDocumentIdentifierLength = 128;

    public static readonly BlockedPopupPageState Empty = new(null, null, null, 0);

    #endregion
}
