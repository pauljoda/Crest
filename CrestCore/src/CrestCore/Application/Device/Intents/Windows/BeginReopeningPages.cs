using CrestCore.Application;

namespace CrestCore.Contracts;

/// The platform starts showing the pages of the windows this launch reopens.
/// The device store says so before the intent returns, until
/// `FinishReopeningPages` or a quit the person agreed to, so the next launch
/// knows when this one ended while they opened. It publishes nothing.
public sealed record BeginReopeningPages : WindowIntent {
    #region Actions - Device

    /// Refused with `SaveFailed` when the device store cannot be written.
    internal override void Apply(Device device, DeviceTurn turn) {
        try {
            device.BeginReopeningPages();
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
    }

    #endregion
}
