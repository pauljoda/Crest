using CrestCore.Application;

namespace CrestCore.Contracts;

/// What a document at `DocumentUrl` of a page of `SpaceId` showing the site at
/// `SiteUrl` hides beyond what its engine blocks. Crest's cosmetic bridge asks
/// once as the document starts (`First`), for the site's hiding rules and
/// procedural filters, and again as elements appear: for the generic rules
/// for their `Classes` and `Ids`, and whether the filter blocks the
/// `Resources` they load. A page on a site where Crest does not block gets
/// `CosmeticFilters.None`.
public sealed record DocumentCosmetics(Guid SpaceId, string SiteUrl, string DocumentUrl, bool First,
    IReadOnlyList<string> Classes, IReadOnlyList<string> Ids, IReadOnlyList<PageResource> Resources) : Query<CosmeticFilters> {
    #region Variables

    public IReadOnlyList<string> Classes {
        get;
        init => field = [.. value];
    } = [.. Classes];

    public IReadOnlyList<string> Ids {
        get;
        init => field = [.. value];
    } = [.. Ids];

    public IReadOnlyList<PageResource> Resources {
        get;
        init => field = [.. value];
    } = [.. Resources];

    #endregion

    #region Actions - Answering

    internal override CosmeticFilters Answer(CrestApp app) =>
        app.Device.Blocks(SpaceId, new WebAddress(SiteUrl).Origin)
            ? app.Filters.Cosmetics(DocumentUrl, First, Classes, Ids, Resources)
            : CosmeticFilters.None;

    #endregion

    #region Actions - Equality

    public bool Equals(DocumentCosmetics? other) => other is not null && SpaceId == other.SpaceId && SiteUrl == other.SiteUrl
        && DocumentUrl == other.DocumentUrl && First == other.First && Classes.SequenceEqual(other.Classes) && Ids.SequenceEqual(other.Ids) && Resources.SequenceEqual(other.Resources);

    public override int GetHashCode() => HashCode.Combine(SpaceId, SiteUrl, DocumentUrl, Classes.Count, Ids.Count, Resources.Count);

    #endregion
}
