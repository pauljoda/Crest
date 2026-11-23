using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Branding` starting over from `House` as a template, icon and colors
/// together, as a Space keeps it. It reads no state, so a host may ask it
/// without an app.
public sealed record ApplyHouse(SpaceBranding Branding, SpaceHouse House) : StandaloneQuery<NormalizedBranding> {
    #region Actions - Answering

    internal override NormalizedBranding Answer(StandaloneContext context) => new(House.Applying(Branding));

    #endregion
}
