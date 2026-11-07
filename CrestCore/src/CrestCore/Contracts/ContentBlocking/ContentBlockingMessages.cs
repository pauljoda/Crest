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

/// A download the platform makes for the core: the list, where it comes from,
/// and the validators of the copy the device holds, which make the download a
/// conditional one.
public sealed record FilterListFetch(FilterList List, string Url, string? EntityTag, string? LastModified);

/// A site where a Space blocks no ads or trackers.
public sealed record SiteContentBlocking(Guid SpaceId, SiteOrigin Origin);

#endregion

#region Changes

/// The filter lists' states changed: one was turned on or off, or updated.
public sealed record FilterListsChanged(IReadOnlyList<FilterListState> Lists) : Change;

/// The content rule lists a page that blocks applies changed, after a list
/// was turned on or off or updated. Pages pick them up on their next
/// navigation.
public sealed record ContentRuleListsChanged(ContentRuleListSet Lists) : Change;

/// The sites where Spaces block nothing changed.
public sealed record SiteContentBlockingChanged(IReadOnlyList<SiteContentBlocking> Sites) : Change;

#endregion

#region Rejections

/// A downloaded filter list is longer than the core keeps.
public sealed record FilterListTooLarge(int LimitBytes) : Rejection;

/// The core holds no content rule list of that identifier, such as one a
/// previous set named.
public sealed record ContentRuleListUnavailable(string Identifier) : Rejection;

#endregion
