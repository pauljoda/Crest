using CrestCore.Application;

namespace CrestCore.Contracts;

/// Forgets every pick the palette of the Space window `WindowId` shows, or of
/// `SpaceId` when the palette spoke for it, made of `Row`, whatever was typed
/// for it.
public sealed record ForgetPaletteChoices(Guid WindowId, PaletteRow Row, Guid? SpaceId = null) : PaletteIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ForgetPaletteChoices(WindowId, SpaceId, Row);

    #endregion
}
