namespace CrestCore.Application;

/// The release this device launched last, which the device store keeps, and
/// the release whose notes a launch that follows an update shows in the first
/// window that asks. A device that has not completed setup shows none, and
/// neither does a launch of the same or an earlier release.
internal sealed partial class Device {
    #region Variables

    /// The release this device launched last, or null before a release that
    /// keeps it launched here.
    private string? launchedRelease;
    /// The release whose notes this launch shows, until a window takes them.
    private string? releaseNotesDue;

    #endregion

    #region Actions - Releases

    /// This launch runs the release `version`, which the device store keeps
    /// as the one launched last. On a device that completed setup, its notes
    /// are due when it follows an update: a later release than the one
    /// launched before, or any release where none was kept, since the
    /// releases before this one kept none.
    internal void NoteLaunchRelease(string version) {
        ArgumentNullException.ThrowIfNull(version);
        lock (gate) {
            var previous = launchedRelease;
            if (previous == version) return;
            launchedRelease = version;
            bool followsUpdate = previous is null || ReleaseVersion.IsLater(version, previous);
            releaseNotesDue = setupCompleted && followsUpdate ? version : null;
            storage?.EnqueueDevice(Records());
        }
    }

    /// The release whose notes this launch shows, for the first window that
    /// asks; null for every other one, and when no notes are due.
    internal string? TakeReleaseNotes() {
        lock (gate) {
            var due = releaseNotesDue;
            releaseNotesDue = null;
            return due;
        }
    }

    #endregion
}
