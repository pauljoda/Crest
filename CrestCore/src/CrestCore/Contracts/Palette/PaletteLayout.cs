using CrestCore.Domain;

namespace CrestCore.Contracts;

/// How the palette arranges its rows: under a header for each kind of
/// result, or as one list ranked across kinds, where each row names its kind.
/// The stored preferences spell a layout as its `Name`, so a name never
/// changes. A layout travels as its index in `All`, so `All` is append-only.
public sealed class PaletteLayout {
    #region Static Variables

    public static readonly PaletteLayout Sections = new(name: "sections", title: "Sections", groupsByKind: true);
    public static readonly PaletteLayout Blended = new(name: "blended", title: "Blended", groupsByKind: false);

    /// The layouts, in the order the settings offer them.
    public static IReadOnlyList<PaletteLayout> All { get; } = [Sections, Blended];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the settings call the layout.
    [Localized]
    public string Title { get; }

    /// Rows stay under the header of their kind.
    public bool GroupsByKind { get; }

    #endregion

    #region Constructors

    private PaletteLayout(string name, string title, bool groupsByKind) {
        Name = name;
        Title = title;
        GroupsByKind = groupsByKind;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteLayout? Named(string? name) => All.FirstOrDefault(layout => layout.Name == name);

    #endregion
}
