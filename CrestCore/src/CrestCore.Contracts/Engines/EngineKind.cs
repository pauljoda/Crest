namespace CrestCore.Contracts;

/// A browsing engine Crest can host pages on. A composition registers the
/// engines it carries, one of them as the default, and each page belongs to
/// one engine. A kind travels as its index in `All`, so `All` is append-only.
public sealed class EngineKind {
    #region Variables

    public static readonly EngineKind Chromium = new(name: "chromium", title: "Chromium");
    public static readonly EngineKind WebKit = new(name: "webkit", title: "WebKit");

    public static IReadOnlyList<EngineKind> All { get; } = [Chromium, WebKit];

    public string Name { get; }

    /// The engine's name as the person reads it, where Crest says which
    /// engine hosts a page.
    [Localized]
    public string Title { get; }

    public string TitleComment { get; } = "The name of a browser engine. Keep the product name as it is.";

    #endregion

    #region Constructors

    private EngineKind(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static EngineKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}
