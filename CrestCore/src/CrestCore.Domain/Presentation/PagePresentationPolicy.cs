namespace CrestCore.Domain;

/// Chooses the page surface for a selected tab from its kind and its live
/// page's state. A navigation failure outranks a renderer failure.
public static class PagePresentationPolicy {
    #region Actions - Presentation

    public static PagePresentation Resolve(PagePresentationSelection selection, bool hasActivePage,
        bool hasNavigationFailure, bool hasProcessFailure, PageUnloadedBehavior unloadedBehavior) => selection switch {
            PagePresentationSelection.None => PagePresentation.NoSelection,
            PagePresentationSelection.NativeContent => PagePresentation.NativeContent,
            PagePresentationSelection.StartPage => PagePresentation.StartPage,
            _ when !hasActivePage => unloadedBehavior == PageUnloadedBehavior.RestoreAutomatically
                ? PagePresentation.AutomaticRestore : PagePresentation.Unloaded,
            _ when hasNavigationFailure => PagePresentation.NavigationFailure,
            _ when hasProcessFailure => PagePresentation.ProcessFailure,
            _ => PagePresentation.LivePage
        };

    #endregion
}
