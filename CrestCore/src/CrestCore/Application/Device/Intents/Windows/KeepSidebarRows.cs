using CrestCore.Application;

namespace CrestCore.Contracts;

/// The tabs one window's sidebar keeps on screen inside the collapsed folders
/// of a Space, such as those a folder kept loaded when it closed, in place of
/// what it reported before. A tab the window then falls back to may be one of
/// them. The window keeps them in memory only, and it publishes nothing.
public sealed record KeepSidebarRows(Guid WindowId, Guid SpaceId, IReadOnlyList<Guid> TabIds) : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        lock (device.Gate) window.KeepRows(SpaceId, TabIds);
    }

    #endregion
}
