namespace CrestCore.Contracts;

/// What media a page runs now: audio or video playing, the camera or the
/// microphone capturing, or a video in Picture in Picture.
[Flags]
public enum PageMediaActivity {
    None = 0,
    Playing = 1 << 0,
    Capturing = 1 << 1,
    PictureInPicture = 1 << 2
}
