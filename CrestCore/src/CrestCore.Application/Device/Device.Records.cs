using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed partial class Device {
    #region Actions - Adoption

    /// Carries the window records an installed release kept into the device
    /// store once, saving them before returning. Older records fold in the
    /// selection that release kept in the session. A device without a file,
    /// or one that adopted them before, publishes nothing.
    private void Adopt(AdoptWindowRecords intent, ChangeFeed changes) {
        Guid workspaceId;
        if (storage is not { } target) return;
        lock (gate) {
            if (adopted.Contains(DeviceAdoption.WindowRecords) || persistentWorkspace is not { } persistent) return;
            workspaceId = persistent;
        }
        var spaces = Workspace(workspaceId).Current.Spaces.Select(space => space.Id).ToArray();
        var legacy = LegacyWindowRecord.DecodeAll(intent.Records);
        DeviceRecords carried;
        long used;
        lock (gate) {
            used = lastUse;
            var records = new Dictionary<Guid, SavedWindow>(saved);
            foreach (var record in legacy.Where(record => !records.ContainsKey(record.Id)))
                records[record.Id] = record.Record(spaces, legacyTabs, ++used);
            carried = Records().Adopting(DeviceAdoption.WindowRecords) with {
                Windows = [.. records.Values.OrderBy(record => record.Used).TakeLast(MaximumSavedWindows)]
            };
        }
        try {
            target.SaveDevice(carried);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
        lock (gate) {
            saved.Clear();
            foreach (var record in carried.Windows) saved[record.Id] = record;
            lastUse = Math.Max(lastUse, used);
            adopted.Add(DeviceAdoption.WindowRecords);
        }
        changes.Publish(new WindowRecordsAdopted([.. legacy.Select(record => record.Layout)]));
    }

    #endregion
}
