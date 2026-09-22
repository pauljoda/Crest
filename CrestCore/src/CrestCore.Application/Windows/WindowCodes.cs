using CrestCore.Domain;

namespace CrestCore.Application;

/// Wire spellings for the window policy operations. They match the native
/// window-state projection's case names.
internal static class WindowCodes {
    #region Variables

    public const string Window = "window";
    public const string Space = "space";
    public const string First = "first";
    public const string None = "none";

    #endregion

    #region Actions - Encoding

    public static string Selection(WindowTabSelection selection) => selection switch {
        WindowTabSelection.Window => Window,
        WindowTabSelection.Space => Space,
        WindowTabSelection.First => First,
        _ => None
    };

    #endregion
}
