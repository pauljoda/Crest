using CrestCore.Application;

namespace CrestCore.Contracts;

/// Records where the floating Picture in Picture window was left, or forgets it
/// when `Frame` is null. The persistent workspace keeps it on this device with
/// the other app-wide preferences; it never syncs. A frame no window could have
/// is rejected.
public sealed record SetPictureInPictureFrame(Guid WorkspaceId, PictureInPictureFrame? Frame) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        if (Frame is { IsValid: false }) throw new Rejected(new InvalidPictureInPictureFrame());
        return workspace.Preferred(turn.Basis, (turn.Basis.AppPreferences ?? AppPreferences.Default) with { PictureInPictureFrame = Frame });
    }

    #endregion
}
