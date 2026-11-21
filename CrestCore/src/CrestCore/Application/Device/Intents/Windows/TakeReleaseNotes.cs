using CrestCore.Application;

namespace CrestCore.Contracts;

/// A window over the persistent session finished opening for the launch. When
/// the launch follows an update, the first window to send it publishes
/// `ReleaseNotesDue`, and the window opens the release's notes.
public sealed record TakeReleaseNotes : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        if (device.TakeReleaseNotes() is { } version) turn.Changes.Publish(new ReleaseNotesDue(version));
    }

    #endregion
}
