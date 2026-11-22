using CrestCore.Application;

namespace CrestCore.Contracts;

/// `Preferences` with the section `Source` standing at `Index` among the
/// sections, as a drag or a move command leaves it. It reads no state, so
/// Settings asks it without an app.
public sealed record PaletteSectionMove(PalettePreferences Preferences, PaletteSource Source, int Index) : StandaloneQuery<PalettePreferences> {
    #region Actions - Answering

    internal override PalettePreferences Answer(StandaloneContext context) => Preferences.Restored().MovingSection(Source, Index);

    #endregion
}
