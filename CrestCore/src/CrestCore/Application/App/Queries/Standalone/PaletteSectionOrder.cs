using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Preferences` with the sections in their default order, each kept on or
/// off as the person set it. It reads no state, so Settings asks it without
/// an app.
public sealed record PaletteSectionOrder(PalettePreferences Preferences) : StandaloneQuery<PalettePreferences> {
    #region Actions - Answering

    internal override PalettePreferences Answer(StandaloneContext context) => Preferences.Restored().RestoringSectionOrder();

    #endregion
}
