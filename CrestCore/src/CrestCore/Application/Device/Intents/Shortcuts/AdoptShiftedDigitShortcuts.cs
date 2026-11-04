using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Names, once, each saved chord that holds Shift with the symbol a digit key
/// types under it, as earlier releases recorded them, by that digit instead,
/// as the catalog and the recorder now name them. `Digits` are the digit keys
/// of the keyboard layout in use. A chord whose digit another offered command
/// already answers to keeps its symbol. The store is written before the intent
/// returns; a device that adopted them before, or keeps no file, changes
/// nothing and still publishes its bindings.
public sealed record AdoptShiftedDigitShortcuts(IReadOnlyList<ShiftedDigit> Digits) : ShortcutIntent {
    #region Actions - Device

    internal override void Apply(Device device, ShortcutTurn turn) {
        lock (device.Gate) {
            Adopt(device, turn);
            turn.Changes.Publish(device.Shortcuts(turn.Offered));
        }
    }

    /// Renames the shifted digits once and saves them before returning. The
    /// caller holds the device lock.
    private void Adopt(Device device, ShortcutTurn turn) {
        if (device.Storage is not { } target || device.Adopted.Contains(DeviceAdoption.ShiftedDigitShortcuts)) return;
        var renamed = device.ShortcutOverrides.ReadingShiftedDigits(Digits, turn.Offered, device.Platform);
        var carried = device.Records().Adopting(DeviceAdoption.ShiftedDigitShortcuts) with { Shortcuts = renamed };
        try {
            target.SaveDevice(carried);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
        device.ShortcutOverrides = renamed;
        device.Adopted.Add(DeviceAdoption.ShiftedDigitShortcuts);
        // Records handed to the store before this carry nothing adopted; these supersede them.
        target.EnqueueDevice(device.Records());
    }

    #endregion
}
