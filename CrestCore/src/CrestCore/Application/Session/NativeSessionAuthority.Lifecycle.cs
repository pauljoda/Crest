using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Opening

    /// A new tab in `placement`'s section showing `content`: a page titled by
    /// its title or host, a native view with the title and symbol it was
    /// given, or the Start Page. A saved or pinned page belongs to its address.
    /// Refused with `InvalidTabContent` for content that names both.
    internal TabState NewTab(Guid id, TabContent content, TabPlacement placement, DateTimeOffset now) {
        if (content.Address is not null && content.View is not null) throw new Rejected(new InvalidTabContent(id));
        var kind = content.View is { } view ? TabKind.Of(view) : content.Address is null ? TabKind.StartPage : TabKind.Web;
        var address = content.Address is { } requested ? PageAddress(requested) : null;
        var title = address is not null ? PageTitle(address, content.Title) : kind.Name;
        var native = content.View is { } shown ? new NativeTabContent(shown.Name) : null;
        return new TabState(id, title, address?.OriginalString, native, placement.IsDurable ? address?.OriginalString : null,
            kind.Symbol, FaviconUrl: null, IconAccent: null, StoredIconMode: null, placement, FolderId: null, SplitGroupId: null, now,
            PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null, KeepsPageLoaded: false);
    }

    /// `address` as a page loads it. Refused with `UnsupportedAddress` for one
    /// that is not absolute.
    private static Uri PageAddress(string address) =>
        Uri.TryCreate(address, UriKind.Absolute, out var parsed) ? parsed : throw new Rejected(new UnsupportedAddress(address));

    /// What a page is called until it reports its own title: `title`, or its
    /// host, or its whole address when it has no host.
    private static string PageTitle(Uri address, string? title) =>
        !string.IsNullOrEmpty(title) ? title : address.Host.Length > 0 ? address.Host : address.OriginalString;

    /// Where among the open tabs a new tab the person opens goes.
    internal NewTabPosition PositionForNewTabs(SessionState basis) => Preferences(basis).NewTabPosition;

    /// Whether a new tab the person opens from a tab in a folder opens at the
    /// end of that folder, rather than among the open tabs.
    internal bool NewTabsJoinFolder(SessionState basis) => Preferences(basis).NewTabsJoinFolder;

    #endregion

    #region Actions - Closing

    /// Where a tab in `placement`'s section returns when closing puts its page
    /// away, as the app's preferences choose for that section; null for a
    /// section whose tabs closing archives.
    internal SavedTabClosePolicy? ClosePolicy(SessionState basis, TabPlacement placement) =>
        placement.ClosePolicy(Preferences(basis));

    #endregion
}
