using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed record SessionTabCopy(Guid Source, Guid Copy) {
    #region Actions - Publishing

    public TabCopied Copied(Guid workspaceId) => new(workspaceId, Source, Copy);

    #endregion
}

/// A tab's image: when `Adopts`, the one `PageId` reported, or with no page
/// the one the command's issuer offered; otherwise none.
internal sealed record SessionFaviconUpdate(Guid TabId, bool Adopts, Guid? PageId = null) {
    #region Actions - Publishing

    public TabFaviconAssigned Assigned(Guid workspaceId) => new(workspaceId, TabId, Adopts, PageId);

    #endregion
}

/// A Quick Window's or Peek's page became a tab, which takes the live page
/// when `AdoptsPage`.
internal sealed record SessionTransientPromotion(Guid PageId, Guid TabId, bool AdoptsPage) {
    #region Actions - Publishing

    public TransientPagePromoted Promoted(Guid workspaceId) => new(workspaceId, PageId, TabId, AdoptsPage);

    #endregion
}

/// The tabs a command copied, the image it assigned and the transient page it
/// kept as a tab, which comparing the sessions before and after it cannot tell.
internal sealed record SessionTabEvents(IReadOnlyList<SessionTabCopy> Copies, SessionFaviconUpdate? Favicon,
    SessionTransientPromotion? Promotion = null) {
    #region Static Variables

    public static SessionTabEvents None { get; } = new([], null);

    #endregion

    #region Actions - Publishing

    /// The changes that tell a reader of `workspaceId` what happened.
    public IEnumerable<Change> Changes(Guid workspaceId) =>
        Copies.Select(copy => (Change)copy.Copied(workspaceId))
            .Concat(Favicon is { } favicon ? [favicon.Assigned(workspaceId)] : [])
            .Concat(Promotion is { } promotion ? [promotion.Promoted(workspaceId)] : []);

    #endregion
}
