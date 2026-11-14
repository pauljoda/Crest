using CrestCore.Application;

namespace CrestCore.Contracts;

/// The WebKit content-rule source of the compiled list `Identifier`, for a
/// rule-list store that does not hold it yet. Refused for an identifier the
/// core no longer holds.
public sealed record ContentRuleListSource(string Identifier) : Query<ContentRuleList> {
    #region Actions - Answering

    internal override ContentRuleList Answer(CrestApp app) => app.Filters.Source(Identifier);

    #endregion
}
