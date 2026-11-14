namespace CrestCore.Domain;

/// The `$removeparam` filters of one filter list's text, read once, and how
/// an address leaves out the query parameters a set of lists removes. The
/// lists act as one: an exception or a `badfilter` filter in any of them
/// holds for the filters of every one.
internal sealed class ParameterFilterList {
    #region Variables

    private readonly IReadOnlyList<ParameterFilter> filters;
    /// The spellings this list's `badfilter` filters cancel.
    private readonly IReadOnlySet<string> cancelled;

    /// How many filters the list holds that may apply to a copied address.
    public int Count => filters.Count;

    #endregion

    #region Constructors

    private ParameterFilterList(IReadOnlyList<ParameterFilter> filters, IReadOnlySet<string> cancelled) {
        this.filters = filters;
        this.cancelled = cancelled;
    }

    #endregion

    #region Actions - Reading

    /// The filters of `text`, a list in uBlock Origin or AdGuard syntax whose
    /// conditional blocks are resolved; every line that is not a
    /// `$removeparam` filter that may apply to a copied address is skipped.
    public static ParameterFilterList Read(string text) {
        ArgumentNullException.ThrowIfNull(text);
        var filters = new List<ParameterFilter>();
        var cancelled = new HashSet<string>(StringComparer.Ordinal);
        foreach (string line in text.Split('\n')) {
            if (ParameterFilter.Read(line) is not { } filter) continue;
            if (filter.Cancels) cancelled.Add(filter.Spelling);
            else filters.Add(filter);
        }
        return new(filters, cancelled);
    }

    #endregion

    #region Actions - Cleaning

    /// `address` without the parameters the filters of `lists` that apply to
    /// it remove, unless an exception that applies keeps them, or as spelled
    /// when an exception that applies keeps every parameter.
    public static string Cleaned(LinkAddress address, IReadOnlyList<ParameterFilterList> lists) {
        ArgumentNullException.ThrowIfNull(address);
        ArgumentNullException.ThrowIfNull(lists);
        if (address.Parameters.Count == 0) return address.Spelling;
        var cancelled = lists.SelectMany(list => list.cancelled).ToHashSet(StringComparer.Ordinal);
        var applying = lists.SelectMany(list => list.filters)
            .Where(filter => !cancelled.Contains(filter.Spelling) && filter.Applies(address)).ToList();
        var exceptions = applying.Where(filter => filter.IsException).ToList();
        var removing = applying.Where(filter => !filter.IsException).ToList();
        if (removing.Count == 0 || exceptions.Any(exception => exception.NamesEverything)) return address.Spelling;
        return address.Without(parameter => removing.Any(filter => filter.Names(parameter))
            && !exceptions.Any(exception => exception.Names(parameter)));
    }

    #endregion
}
