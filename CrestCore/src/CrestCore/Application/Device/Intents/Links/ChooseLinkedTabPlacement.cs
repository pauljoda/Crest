using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Chooses where a tab opened from a link goes: a modified or middle click, a
/// page's new tab or window, the context menu's new tab, and a kept Peek.
public sealed record ChooseLinkedTabPlacement(NewTabPlacement Placement) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseLinks(turn.Changes, links => links with { LinkedTabPlacement = Placement });

    #endregion
}
