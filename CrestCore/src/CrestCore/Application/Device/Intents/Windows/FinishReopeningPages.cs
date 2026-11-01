using CrestCore.Application;

namespace CrestCore.Contracts;

/// The pages this launch reopened have settled, so a launch that ends from
/// now on did not end while they opened. It publishes nothing.
public sealed record FinishReopeningPages : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.FinishReopeningPages();

    #endregion
}
