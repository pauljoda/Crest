using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The search area: custom engine admission. It holds no state; a Space's
/// engines are saved by the session's search-engine commands.
public sealed class Search {
    #region Actions - Custom engines

    /// The engine as Crest would save it. Throws `Rejected` with the first
    /// rule it breaks: a flaw of its own, a name another engine uses, or the
    /// Space's engine limit.
    public CustomSearchEngine Answer(CustomSearchEngineAdmission query) {
        ArgumentNullException.ThrowIfNull(query);
        var engine = query.Engine;
        var provider = SearchProvider.Admit(engine.Id, engine.Name, engine.SearchTemplate, engine.SuggestionTemplate);
        SearchPreferences.Admit(provider, [.. query.Existing.Select(existing => (SearchProvider.CustomId(existing.Id), existing.Name))]);
        return new(engine.Id, provider.Title, provider.SearchTemplate, provider.SuggestionTemplate);
    }

    #endregion
}
