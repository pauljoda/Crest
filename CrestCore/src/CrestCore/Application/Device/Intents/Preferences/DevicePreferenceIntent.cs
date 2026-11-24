using CrestCore.Application;

namespace CrestCore.Contracts;

/// A change to how this device shows pages, where its Spaces' downloads go,
/// which actions sit on top of Site Controls, or the choices an installed
/// release kept for them. The device store keeps them and never syncs them.
public abstract record DevicePreferenceIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the device, publishing what it changed to the
    /// turn's changes.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.Handle(this, app.DeviceTurn(changes)));

    #endregion
}
