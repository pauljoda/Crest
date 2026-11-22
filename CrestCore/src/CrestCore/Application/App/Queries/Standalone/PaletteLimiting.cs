using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Preferences` with `Source` showing at most `Limit` rows, or its own
/// number when `Limit` is that number. It reads no state, so Settings asks it
/// without an app.
public sealed record PaletteLimiting(PalettePreferences Preferences, PaletteSource Source, int Limit) : StandaloneQuery<PalettePreferences> {
    #region Actions - Answering

    internal override PalettePreferences Answer(StandaloneContext context) => Preferences.Restored().Limiting(Source, Limit);

    #endregion
}
