using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Chooses where a new tab opens: a Start Page, an address typed in the
/// command bar, a link another app hands Crest, and a kept Quick Window.
public sealed record ChooseNewTabPlacement(NewTabPlacement Placement) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links => links with { NewTabPlacement = Placement });

    #endregion
}
