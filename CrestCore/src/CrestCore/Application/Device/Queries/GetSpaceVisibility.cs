using CrestCore.Application;

namespace CrestCore.Contracts;

/// The Spaces of the person's own session this device hides.
public sealed record GetSpaceVisibility : Query<SpaceVisibility> {
    #region Actions - Answering

    internal override SpaceVisibility Answer(CrestApp app) => app.Device.SpaceVisibility;

    #endregion
}
