namespace CrestCore.Contracts;

/// What a page's engine shows now: the address of its document, the address
/// a navigation that has not committed is heading to, its title, whether it
/// is loading, whether it can go back or forward, how secure its connection
/// is and what media it runs. A binding reports it when it changes, at most
/// once per turn, and the latest report wins.
public sealed record PageSnapshot(string? Url, string? PendingUrl, string Title, bool IsLoading, bool CanGoBack,
    bool CanGoForward, PageSecurity Security, PageMediaActivity Media) {
    #region Static Variables

    /// A page its engine has shown nothing in yet.
    public static PageSnapshot Blank { get; } = new(Url: null, PendingUrl: null, Title: "", IsLoading: false, CanGoBack: false,
        CanGoForward: false, PageSecurity.None, PageMediaActivity.None);

    #endregion
}
