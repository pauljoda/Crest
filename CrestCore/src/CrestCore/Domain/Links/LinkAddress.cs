using CrestCore.Contracts;

namespace CrestCore.Domain;

/// An http or https address a person copies, read into the parts link
/// cleaning edits, which keep their spelling, and into the form filter
/// patterns match.
internal sealed class LinkAddress {
    #region Static Variables

    private const string SchemeSeparator = "://";

    #endregion

    #region Variables

    /// The address as spelled.
    public string Spelling { get; }

    /// The host in lowercase ASCII.
    public string Host { get; }

    /// The scheme and authority as spelled.
    public string Origin { get; }

    /// The path as spelled, empty when the address has none.
    public string Path { get; }

    /// The query's parameters in order, without empty ones.
    public IReadOnlyList<QueryParameter> Parameters { get; }

    /// The fragment with its `#`, or empty.
    public string Fragment { get; }

    /// What filter patterns match: the scheme in lowercase, the host in
    /// lowercase ASCII, then the port, the path, `/` when there is none, and
    /// the query as spelled, without the fragment.
    public string Location { get; }

    /// Where the host starts and ends in `Location`.
    public int HostStart { get; }
    public int HostEnd { get; }

    #endregion

    #region Constructors

    private LinkAddress(string spelling, string scheme, string host, string origin, string port, string path, string? query,
        string fragment) {
        Spelling = spelling;
        Host = host;
        Origin = origin;
        Path = path;
        Parameters = query is null ? [] : [.. query.Split('&').Where(piece => piece.Length > 0).Select(piece => new QueryParameter(piece))];
        Fragment = fragment;
        HostStart = scheme.Length + SchemeSeparator.Length;
        HostEnd = HostStart + host.Length;
        Location = $"{scheme}{SchemeSeparator}{host}{port}{(path.Length == 0 ? "/" : path)}{(query is null ? "" : $"?{query}")}";
    }

    #endregion

    #region Actions - Reading

    /// `spelling` read as an http or https address, or null for any other
    /// address or one that does not read.
    public static LinkAddress? Read(string spelling) {
        ArgumentNullException.ThrowIfNull(spelling);
        if (!Uri.TryCreate(spelling, UriKind.Absolute, out var parsed) || WebScheme.Named(parsed.Scheme) is null
            || parsed.IdnHost.Length == 0
            || !spelling.StartsWith($"{parsed.Scheme}{SchemeSeparator}", StringComparison.OrdinalIgnoreCase))
            return null;
        int hash = spelling.IndexOf('#', StringComparison.Ordinal);
        string fragment = hash < 0 ? "" : spelling[hash..];
        string beforeFragment = hash < 0 ? spelling : spelling[..hash];
        int question = beforeFragment.IndexOf('?', StringComparison.Ordinal);
        string beforeQuery = question < 0 ? beforeFragment : beforeFragment[..question];
        int authorityStart = parsed.Scheme.Length + SchemeSeparator.Length;
        int pathStart = beforeQuery.IndexOf('/', authorityStart);
        string origin = pathStart < 0 ? beforeQuery : beforeQuery[..pathStart];
        // The port follows the host, past any credentials and an IPv6
        // address's brackets.
        int hostStart = Math.Max(authorityStart, origin.LastIndexOf('@') + 1);
        int bracket = origin[hostStart..].StartsWith('[') ? origin.IndexOf(']', hostStart) : -1;
        int colon = origin.IndexOf(':', bracket < 0 ? hostStart : bracket);
        return new(spelling, parsed.Scheme, parsed.IdnHost.ToLowerInvariant(), origin, colon < 0 ? "" : origin[colon..],
            pathStart < 0 ? "" : beforeQuery[pathStart..], question < 0 ? null : beforeFragment[(question + 1)..], fragment);
    }

    #endregion

    #region Actions - Spelling

    /// The address with `path` and only `parameters`, each as spelled; the
    /// `?` goes when none is left, and the fragment stays.
    public string Spelled(string path, IEnumerable<QueryParameter> parameters) {
        ArgumentNullException.ThrowIfNull(path);
        ArgumentNullException.ThrowIfNull(parameters);
        string query = string.Join('&', parameters.Select(parameter => parameter.Spelling));
        return $"{Origin}{path}{(query.Length == 0 ? "" : $"?{query}")}{Fragment}";
    }

    /// The address without the parameters `removes` picks, or as spelled
    /// when it picks none.
    public string Without(Func<QueryParameter, bool> removes) {
        ArgumentNullException.ThrowIfNull(removes);
        var kept = Parameters.Where(parameter => !removes(parameter)).ToList();
        return kept.Count == Parameters.Count ? Spelling : Spelled(Path, kept);
    }

    #endregion
}
