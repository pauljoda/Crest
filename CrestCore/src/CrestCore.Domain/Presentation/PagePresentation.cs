namespace CrestCore.Domain;

/// What a page surface shows for the selected tab.
public enum PagePresentation {
    NoSelection,
    StartPage,
    NativeContent,
    LivePage,
    NavigationFailure,
    ProcessFailure,
    Unloaded,
    AutomaticRestore
}
