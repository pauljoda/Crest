using CrestCore.Contracts;

namespace CrestCore.Application;

/// Which of an engine's templates a `search.url` request fills. A request
/// spells a purpose as its `Name`.
internal sealed class SearchUrlPurpose {
    #region Variables

    public static readonly SearchUrlPurpose Search = new(name: "search", url: (provider, query) => provider.Search(query));
    public static readonly SearchUrlPurpose Suggestions = new(name: "suggestions", url: (provider, query) => provider.Suggest(query));

    public static IReadOnlyList<SearchUrlPurpose> All { get; } = [Search, Suggestions];

    private readonly Func<SearchProvider, string, string?> url;

    public string Name { get; }

    #endregion

    #region Constructors

    private SearchUrlPurpose(string name, Func<SearchProvider, string, string?> url) {
        Name = name;
        this.url = url;
    }

    #endregion

    #region Actions - Lookup

    public static SearchUrlPurpose? Named(string? name) => All.FirstOrDefault(purpose => purpose.Name == name);

    #endregion

    #region Actions - Queries

    /// The engine's URL for `query` for this purpose, or null when the engine has none.
    public string? Url(SearchProvider provider, string query) {
        ArgumentNullException.ThrowIfNull(provider);
        return url(provider, query);
    }

    #endregion
}
