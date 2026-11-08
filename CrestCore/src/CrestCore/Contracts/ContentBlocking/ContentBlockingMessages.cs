namespace CrestCore.Contracts;

#region Models

/// A content rule list: the versioned identifier a rule-list store compiles it
/// under, and its WebKit content-rule JSON source.
public sealed record ContentRuleList(string Identifier, string Source);

/// The content rule lists a page that blocks applies, named by the versioned
/// identifiers a rule-list store compiles them under. An identifier changes
/// whenever its rules do, so a store that holds one never compiles it again;
/// `ContentRuleListSource` answers the source of one it lacks.
public sealed record ContentRuleListSet(IReadOnlyList<string> Identifiers) {
    #region Variables

    public IReadOnlyList<string> Identifiers {
        get;
        init => field = [.. value];
    } = [.. Identifiers];

    #endregion

    #region Actions - Equality

    public bool Equals(ContentRuleListSet? other) => other is not null && Identifiers.SequenceEqual(other.Identifiers);

    public override int GetHashCode() => Identifiers.Count == 0 ? 0 : HashCode.Combine(Identifiers.Count, Identifiers[0]);

    #endregion
}

/// A filter list as the settings show it: whether it is on, and when its copy
/// was last brought up to date. `IsFailing` says the last attempt to update it
/// failed; the copy the device has stays in use.
public sealed record FilterListState(FilterList List, bool IsOn, DateTimeOffset? UpdatedAt, bool IsFailing);

/// A download the platform makes for the core, named by `Id`: a filter list,
/// one the person added, or the resources the filter's scriptlets and
/// redirects use. `Url` is where it comes from, and the validators of the copy
/// the device holds make the download a conditional one.
public sealed record FilterDownload(Guid Id, string Url, string? EntityTag, string? LastModified);

/// A filter list the person added by its address, which every Space that
/// blocks applies while it is on.
public sealed record CustomFilterList(Guid Id, string Url, bool IsOn);

/// A list the person added, as the settings show it: what the list calls
/// itself, or its address's host before a download names it, and when its
/// copy was last brought up to date. `IsFailing` says the last attempt to
/// update it failed, and `IsTooLarge` that it brought a list larger, or with
/// more rules, than the core takes.
public sealed record CustomFilterListState(CustomFilterList List, string Title, DateTimeOffset? UpdatedAt, bool IsFailing,
    bool IsTooLarge);

/// Every filter list as the settings show it: the catalog's, in
/// `FilterList.All` order; the ones the person added, in the order added; and
/// the person's own filters, in the lists' syntax.
public sealed record FilterLists(IReadOnlyList<FilterListState> Lists, IReadOnlyList<CustomFilterListState> CustomLists,
    string CustomFilters) {
    #region Variables

    public IReadOnlyList<FilterListState> Lists {
        get;
        init => field = [.. value];
    } = [.. Lists];

    public IReadOnlyList<CustomFilterListState> CustomLists {
        get;
        init => field = [.. value];
    } = [.. CustomLists];

    #endregion

    #region Actions - Equality

    public bool Equals(FilterLists? other) => other is not null && Lists.SequenceEqual(other.Lists)
        && CustomLists.SequenceEqual(other.CustomLists) && CustomFilters == other.CustomFilters;

    public override int GetHashCode() => HashCode.Combine(Lists.Count, CustomLists.Count, CustomFilters.Length);

    #endregion
}

/// A site where a Space blocks no ads or trackers.
public sealed record SiteContentBlocking(Guid SpaceId, SiteOrigin Origin);

/// What an element of a document loads from its address.
public enum PageResourceKind {
    /// A frame's document.
    Frame,
    /// An image.
    Image,
    /// An embedded object or plug-in.
    Object
}

/// An element of a document that loads from `Url`, which the content filter
/// may block, leaving the element an empty box.
public sealed record PageResource(PageResourceKind Kind, string Url);

/// What a document of a page that blocks hides beyond what its engine blocks
/// itself: style rules, one `selector{display:none!important}` per line; the
/// filter lists' procedural filters and actions for the document, each as the
/// content filter's JSON, which Crest's cosmetic bridge applies; and the
/// addresses of elements to collapse because the filter blocks what they
/// load. `Blocks` is false for a page that blocks nothing, and the bridge
/// then stops.
public sealed record CosmeticFilters(bool Blocks, string Style, IReadOnlyList<string> Procedural, IReadOnlyList<string> Collapse) {
    #region Static Variables

    /// The answer for a page that blocks nothing.
    public static CosmeticFilters None { get; } = new(false, "", [], []);

    #endregion

    #region Variables

    public IReadOnlyList<string> Procedural {
        get;
        init => field = [.. value];
    } = [.. Procedural];

    public IReadOnlyList<string> Collapse {
        get;
        init => field = [.. value];
    } = [.. Collapse];

    #endregion

    #region Actions - Equality

    public bool Equals(CosmeticFilters? other) => other is not null && Blocks == other.Blocks && Style == other.Style
        && Procedural.SequenceEqual(other.Procedural) && Collapse.SequenceEqual(other.Collapse);

    public override int GetHashCode() => HashCode.Combine(Blocks, Style, Procedural.Count, Collapse.Count);

    #endregion
}

#endregion

#region Changes

/// The filter lists changed: one was turned on or off, added, removed or
/// updated, or the person's own filters changed.
public sealed record FilterListsChanged(FilterLists Lists) : Change;

/// The content rule lists a page that blocks applies changed, after a list
/// was turned on or off or updated. Pages pick them up on their next
/// navigation.
public sealed record ContentRuleListsChanged(ContentRuleListSet Lists) : Change;

/// The sites where Spaces block nothing changed.
public sealed record SiteContentBlockingChanged(IReadOnlyList<SiteContentBlocking> Sites) : Change;

#endregion

#region Rejections

/// The core holds no content rule list of that identifier, such as one a
/// previous set named.
public sealed record ContentRuleListUnavailable(string Identifier) : Rejection;

/// A filter list's address is not an https address the core can download.
public sealed record FilterListAddressInvalid(string Url) : Rejection;

/// The person added as many filter lists as the core keeps.
public sealed record CustomFilterListLimitReached(int Limit) : Rejection;

/// The person's own filters are longer than the core keeps.
public sealed record CustomFiltersTooLarge(int LimitBytes) : Rejection;

/// A picked element's selector, or the page it was picked on, cannot make a
/// rule that hides it.
public sealed record ElementSelectorInvalid(string Selector) : Rejection;

#endregion
