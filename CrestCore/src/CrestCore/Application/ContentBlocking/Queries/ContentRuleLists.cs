using CrestCore.Application;

namespace CrestCore.Contracts;

/// The content rule lists a page that blocks applies now. Before any filter
/// list arrives they hold Crest's own baseline rules; `ContentRuleListsChanged`
/// names the next ones.
public sealed record ContentRuleLists : Query<ContentRuleListSet> {
    #region Actions - Answering

    internal override ContentRuleListSet Answer(CrestApp app) => app.Filters.Rules();

    #endregion
}
