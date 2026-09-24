namespace CrestCore.Domain;

/// Quick Window archive-on-dismissal and retargeting rules shared by the Mac
/// window and the mobile overlay.
public static class QuickWindowPolicy {
    #region Actions - Archive

    /// Dismissing a Quick Window files its page in the archive once, unless the
    /// page was promoted into a tab or there is no page to keep.
    public static bool ArchivesOnDismissal(bool wasArchived, bool wasPromoted, bool hasPage) =>
        !wasArchived && !wasPromoted && hasPage;

    #endregion

    #region Actions - Retargeting

    /// A request is revised when its address or its Space assignment changes.
    /// Moving a page, not an empty lookup, to another Space remembers that
    /// Space for the page's site. `pageUrl` is null for an empty lookup.
    public static QuickWindowRetarget Retarget(QuickWindowPlacement current, QuickWindowPlacement next, string? pageUrl) {
        bool moves = current.SpaceId != next.SpaceId || current.ProfileId != next.ProfileId;
        return new(moves || !string.Equals(current.Url, next.Url, StringComparison.Ordinal), moves && pageUrl is not null);
    }

    #endregion
}
