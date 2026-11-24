using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Branding` wearing `House`'s arms as its icon, keeping its own colors, as
/// a Space keeps it. It reads no state, so a host may ask it without an app.
public sealed record WearHouseCrest(SpaceBranding Branding, SpaceHouse House) : StandaloneQuery<NormalizedBranding> {
    #region Actions - Answering

    internal override NormalizedBranding Answer(StandaloneContext context) => new(House.WearingCrest(Branding));

    #endregion
}
