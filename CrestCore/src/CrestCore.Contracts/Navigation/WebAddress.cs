namespace CrestCore.Contracts;

/// A web page's address as a page, a person or a record spelled it. A page's
/// fragment only points within it, so two spellings that differ only there
/// name one page; an address that is not http or https compares as spelled.
public readonly record struct WebAddress(string Spelling) {
    #region Variables

    /// The address history keeps for the page: an http or https address
    /// without its fragment, or null for one history does not keep.
    public string? Normalized => Uri.TryCreate(Spelling, UriKind.Absolute, out var value)
        && (value.Scheme == Uri.UriSchemeHttp || value.Scheme == Uri.UriSchemeHttps) ? Spelling.Split('#', 2)[0] : null;

    #endregion

    #region Actions - Comparison

    /// Whether both addresses name one page. Everything that asks "is this
    /// still the page I captured?", such as a favicon or a saved address,
    /// asks it here, so a fragment or a scheme history does not keep cannot
    /// make one page look like two.
    public bool IsSamePage(WebAddress other) => (Normalized ?? Spelling) == (other.Normalized ?? other.Spelling);

    #endregion
}
