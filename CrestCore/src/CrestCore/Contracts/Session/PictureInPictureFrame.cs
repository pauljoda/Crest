namespace CrestCore.Contracts;

#region Types

/// A display as the host names it: the stable identifier of the physical
/// screen, such as the UUID the platform reports for a display, which survives
/// a relaunch where a numeric display number does not.
public sealed record ScreenIdentity(string DisplayUuid);

#endregion

/// Where the floating Picture in Picture window was last left: its whole frame
/// in the host's screen coordinates, so a size the person chose comes back with
/// its position, and the screen it was saved on. The core only keeps it. The
/// host decides how to place it again when that screen is gone, and clamps it
/// to what is visible.
public sealed record PictureInPictureFrame(double X, double Y, double Width, double Height, ScreenIdentity Screen) {
    #region Variables

    /// Whether this is a frame a window can have: finite, with a positive size
    /// and a named screen.
    public bool IsValid => double.IsFinite(X) && double.IsFinite(Y) && double.IsFinite(Width) && double.IsFinite(Height)
        && Width > 0 && Height > 0 && !string.IsNullOrWhiteSpace(Screen?.DisplayUuid);

    #endregion
}
