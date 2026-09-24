namespace CrestCore.Contracts;

/// The search engines every Space offers. A Space stores and syncs a built-in
/// choice as the engine's `Name`, which never changes; `SearchProvider` holds
/// each one's templates. A member travels as its index in `All`, so `All` only
/// grows at the end.
public sealed class BuiltInSearchEngine {
    #region Static Variables

    public static readonly BuiltInSearchEngine Google = new(name: "google");
    public static readonly BuiltInSearchEngine DuckDuckGo = new(name: "duckDuckGo");
    public static readonly BuiltInSearchEngine Bing = new(name: "bing");
    public static readonly BuiltInSearchEngine Ecosia = new(name: "ecosia");
    public static readonly BuiltInSearchEngine Brave = new(name: "brave");

    /// The built-in engines, in the order the settings offer them.
    public static IReadOnlyList<BuiltInSearchEngine> All { get; } = [Google, DuckDuckGo, Bing, Ecosia, Brave];

    #endregion

    #region Variables

    public string Name { get; }

    #endregion

    #region Constructors

    private BuiltInSearchEngine(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static BuiltInSearchEngine? Named(string? name) => All.FirstOrDefault(engine => engine.Name == name);

    /// The engine this is, with the templates it searches with.
    public SearchProvider Provider() => SearchProvider.Named(Name)!;

    #endregion
}
