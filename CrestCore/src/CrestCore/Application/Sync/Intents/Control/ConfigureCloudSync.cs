using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sync starts on this device, on when the person keeps it on in the device
/// store, if this build can reach Crest's CloudKit container at all.
public sealed record ConfigureCloudSync(bool CanReachCloud) : CloudSyncControlIntent {
    #region Actions - Sync

    internal override List<CloudSyncStep> Steps(CloudSyncControl control) {
        control.IsEnabled = control.Transport.Device.SyncsWithICloud;
        control.CanReachCloud = CanReachCloud;
        control.Phase = control.IsEnabled ? CloudSyncPhase.Checking : CloudSyncPhase.Disabled;
        return [];
    }

    #endregion
}
