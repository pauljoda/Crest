using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Adds a new Space at the end of the manual setup, named for its place, such
/// as "Space 2", and wearing the accents in turn in the look setup chose; or,
/// given `FromSpaceId`, a Sub-Space of that Space, sharing its group's
/// session, right after the group, named with the next number of its Space's
/// name and wearing its look. Refused with `SpaceLimitReached` when the setup
/// holds as many Spaces as a workspace may.
public sealed record AddSetupSpace(Guid? FromSpaceId = null) : SetupDraftIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSetup(turn.Changes, draft => FromSpaceId is { } from
            ? draft.AddingSubSpace(from, turn.Ids.Next)
            : draft.Adding(turn.Ids.Next, device.SetupLook));

    #endregion
}
