namespace CrestCore.Domain;

/// One parameter of an address's query: as the address spells it, which a
/// cleaned address keeps byte for byte, and as filters read it, with its name
/// and value percent-decoded.
internal sealed class QueryParameter {
    #region Variables

    /// The parameter as the query spells it, between its `&`s.
    public string Spelling { get; }

    public string Name { get; }

    /// The value, or empty for a parameter spelled without `=`.
    public string Value { get; }

    /// `name=value`, which a filter's regular expression is tested against.
    public string Pair { get; }

    #endregion

    #region Constructors

    public QueryParameter(string spelling) {
        ArgumentNullException.ThrowIfNull(spelling);
        Spelling = spelling;
        int equals = spelling.IndexOf('=', StringComparison.Ordinal);
        Name = Uri.UnescapeDataString(equals < 0 ? spelling : spelling[..equals]);
        Value = equals < 0 ? "" : Uri.UnescapeDataString(spelling[(equals + 1)..]);
        Pair = $"{Name}={Value}";
    }

    #endregion
}
