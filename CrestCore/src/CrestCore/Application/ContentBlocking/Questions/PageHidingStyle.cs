using CrestCore.Application;

namespace CrestCore.Contracts;

/// The style sheet that hides what the content filter hides in a page's
/// document at `Url`, which shows the elements of `Classes` and `Ids`: the
/// site's own hiding rules, and the generic ones for those classes and ids.
/// An engine asks for a page that blocks, once per document; a page the core
/// does not host on that engine hides nothing.
public sealed record PageHidingStyle(Guid PageId, string Url, IReadOnlyList<string> Classes, IReadOnlyList<string> Ids)
    : EngineQuestion<string> {
    #region Variables

    public IReadOnlyList<string> Classes {
        get;
        init => field = [.. value];
    } = [.. Classes];

    public IReadOnlyList<string> Ids {
        get;
        init => field = [.. value];
    } = [.. Ids];

    #endregion

    #region Actions - Answering

    internal override string Answer(CrestApp app, Engine engine) =>
        ReferenceEquals(app.Pages.Hosted(PageId)?.Engine, engine) ? app.Filters.HidingStyle(Url, Classes, Ids) : "";

    #endregion

    #region Actions - Equality

    public bool Equals(PageHidingStyle? other) => other is not null && PageId == other.PageId && Url == other.Url
        && Classes.SequenceEqual(other.Classes) && Ids.SequenceEqual(other.Ids);

    public override int GetHashCode() => HashCode.Combine(PageId, Url, Classes.Count, Ids.Count);

    #endregion
}
