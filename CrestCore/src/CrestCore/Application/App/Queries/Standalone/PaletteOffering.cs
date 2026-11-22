using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Preferences` with `Source` offered or not. It reads no state, so
/// Settings asks it without an app.
public sealed record PaletteOffering(PalettePreferences Preferences, PaletteSource Source, bool IsEnabled) : StandaloneQuery<PalettePreferences> {
    #region Actions - Answering

    internal override PalettePreferences Answer(StandaloneContext context) => Preferences.Restored().Offering(Source, IsEnabled);

    #endregion
}
