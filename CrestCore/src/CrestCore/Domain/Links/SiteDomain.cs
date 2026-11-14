using System.Buffers;

namespace CrestCore.Domain;

/// A site as a link filter names it: a domain with every subdomain of it, or,
/// spelled `name.*`, an entity, which is `name` under any public suffix, as
/// uBlock Origin reads `amazon.*`.
internal sealed class SiteDomain {
    #region Static Variables

    private const string AnySuffix = ".*";

    private static readonly SearchValues<char> Letters = SearchValues.Create("abcdefghijklmnopqrstuvwxyz");
    private static readonly SearchValues<char> LabelCharacters = SearchValues.Create("abcdefghijklmnopqrstuvwxyz0123456789-");

    #endregion

    #region Variables

    /// The domain in lowercase, without the `.*` of an entity.
    public string Name { get; }

    /// Whether any public suffix follows `Name`.
    public bool IsEntity { get; }

    #endregion

    #region Constructors

    public SiteDomain(string spelling) {
        ArgumentException.ThrowIfNullOrEmpty(spelling);
        string lowered = spelling.ToLowerInvariant();
        IsEntity = lowered.EndsWith(AnySuffix, StringComparison.Ordinal);
        Name = IsEntity ? lowered[..^AnySuffix.Length] : lowered;
    }

    #endregion

    #region Actions - Matching

    /// Whether `host`, in lowercase ASCII, is the site or one of its
    /// subdomains.
    public bool Holds(string host) {
        ArgumentNullException.ThrowIfNull(host);
        if (!IsEntity)
            return host.EndsWith(Name, StringComparison.Ordinal)
                && (host.Length == Name.Length || host[^(Name.Length + 1)] == '.');
        for (int start = 0; start >= 0 && start < host.Length; start = NextLabel(host, start))
            if (EntityAt(host, start, host.Length)) return true;
        return false;
    }

    /// Whether `text` holds the entity `name` at `start`, a label's start,
    /// followed by a dot and a public suffix that ends at `end`.
    public static bool EntityAt(string text, int start, int end, string name) {
        int suffix = start + name.Length + 1;
        return suffix < end && string.CompareOrdinal(text, start, name, 0, name.Length) == 0 && text[suffix - 1] == '.'
            && IsPublicSuffix(text.AsSpan(suffix, end - suffix));
    }

    private bool EntityAt(string host, int start, int end) => EntityAt(host, start, end, Name);

    /// Where the label after the one at `start` starts in `host`, or -1 after
    /// the last.
    public static int NextLabel(string host, int start) {
        int dot = host.IndexOf('.', start);
        return dot < 0 ? -1 : dot + 1;
    }

    /// Whether `labels` reads as a public suffix: one top-level label of
    /// letters, or an internationalized one, or a short second level under a
    /// two-letter country code, such as `co.uk` or `com.au`.
    public static bool IsPublicSuffix(ReadOnlySpan<char> labels) {
        int dot = labels.IndexOf('.');
        if (dot < 0)
            return labels.Length >= 2 && (!labels.ContainsAnyExcept(Letters)
                || (labels.StartsWith("xn--", StringComparison.Ordinal) && !labels.ContainsAnyExcept(LabelCharacters)));
        var second = labels[..dot];
        var country = labels[(dot + 1)..];
        return second.Length is >= 2 and <= 3 && !second.ContainsAnyExcept(Letters) && country.Length == 2
            && !country.ContainsAnyExcept(Letters);
    }

    #endregion
}
