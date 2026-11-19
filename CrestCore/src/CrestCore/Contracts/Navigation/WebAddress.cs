using System.Text;

namespace CrestCore.Contracts;

/// A web page's address as a page, a person or a record spelled it. A page's
/// fragment only points within it, and escaping a character an address cannot
/// hold changes nothing it names, so two spellings that differ only there name
/// one page; an address that is not http or https compares as spelled.
public readonly record struct WebAddress(string Spelling) {
    #region Static Variables

    private const string Hex = "0123456789ABCDEF";

    /// What a path holds besides letters and digits: RFC 3986's unreserved
    /// characters, its sub-delimiters, `:`, `@` and `/`. A query and a
    /// fragment also hold `?`.
    private const string PathCharacters = "-._~!$&'()*+,;=:@/";
    private const string QueryCharacters = PathCharacters + "?";

    #endregion

    #region Variables

    /// The address history keeps for the page: an http or https address
    /// without its fragment, or null for one history does not keep.
    public string? Normalized => Uri.TryCreate(Spelling, UriKind.Absolute, out var value)
        && WebScheme.Named(value.Scheme) is not null ? Spelling.Split('#', 2)[0] : null;

    /// The web origin a page at this address belongs to, with its host in
    /// ASCII, or null for an address that is not http or https.
    public SiteOrigin? Origin => Uri.TryCreate(Spelling, UriKind.Absolute, out var value) && WebScheme.Named(value.Scheme) is not null
        && value.IdnHost.Length > 0 ? new SiteOrigin(value.Scheme, value.IdnHost, value.Port) : null;

    /// Where an http or https address points: its host, a port other than the
    /// scheme's own, its path, "/" when it has none, and its query. Null for
    /// any other address.
    public string? Location => Uri.TryCreate(Spelling, UriKind.Absolute, out var value) && WebScheme.Named(value.Scheme) is not null
        ? value.GetComponents(UriComponents.Host | UriComponents.Port | UriComponents.PathAndQuery, UriFormat.UriEscaped) : null;

    /// Whether the address shows a web page, or a blank one, rather than one
    /// of the browser's own, an extension's or a file.
    public bool IsWebPage => Normalized is not null || Spelling == "about:blank";

    /// The spelling with each character its path, query or fragment cannot
    /// hold escaped as UTF-8, and each `%` that starts no escape escaped too.
    /// Every escape it already spells, and everything before its path, stays
    /// as spelled, so the address names what it named, and escaping it again
    /// changes nothing. The Apple platforms read an address this way, so the
    /// escapes a page used reach the engine again unchanged.
    public string Escaped {
        get {
            int start = PathStart(Spelling);
            int fragment = Spelling.IndexOf('#', start);
            int end = fragment < 0 ? Spelling.Length : fragment;
            int query = Spelling.IndexOf('?', start, end - start);
            var escaped = new StringBuilder(Spelling.Length + 16).Append(Spelling, 0, start);
            AppendEscaped(escaped, Spelling[start..(query < 0 ? end : query)], PathCharacters);
            if (query >= 0) AppendEscaped(escaped.Append('?'), Spelling[(query + 1)..end], QueryCharacters);
            if (fragment >= 0) AppendEscaped(escaped.Append('#'), Spelling[(fragment + 1)..], QueryCharacters);
            return escaped.ToString();
        }
    }

    /// What names the page: an http or https address escaped and without its
    /// fragment, and any other as spelled.
    private string Page => Normalized is { } page ? new WebAddress(page).Escaped : Spelling;

    #endregion

    #region Actions - Comparison

    /// Whether both addresses name one page. Everything that asks "is this
    /// still the page I captured?", such as a favicon or a saved address,
    /// asks it here, so a fragment, a scheme history does not keep, or an
    /// engine that escapes more than the page did cannot make one page look
    /// like two.
    public bool IsSamePage(WebAddress other) => Page == other.Page;

    /// Whether this http or https address is the one `schemeless`, an
    /// address spelled without its scheme, names when read with this
    /// address's own scheme, ignoring case. A port it spells must be this
    /// address's port; with none, the scheme's own is.
    public bool IsAt(string schemeless) => Uri.TryCreate(Spelling, UriKind.Absolute, out var value)
        && WebScheme.Named(value.Scheme) is not null
        && string.Equals(Location, new WebAddress($"{value.Scheme}://{schemeless}").Location, StringComparison.OrdinalIgnoreCase);

    #endregion

    #region Actions - Escaping

    /// Where the path of `spelling` starts: after its scheme and its
    /// authority, or at its start when it names no scheme.
    private static int PathStart(string spelling) {
        int colon = spelling.IndexOf(':', StringComparison.Ordinal);
        if (colon <= 0 || !char.IsAsciiLetter(spelling[0])) return 0;
        for (int index = 1; index < colon; index++)
            if (!char.IsAsciiLetterOrDigit(spelling[index]) && spelling[index] is not ('+' or '-' or '.')) return 0;
        int start = colon + 1;
        if (string.CompareOrdinal(spelling, start, "//", 0, 2) != 0) return start;
        int end = spelling.IndexOfAny(['/', '?', '#'], start + 2);
        return end < 0 ? spelling.Length : end;
    }

    /// Appends `part` with each character outside letters, digits and
    /// `allowed` escaped as UTF-8, keeping each escape it spells.
    private static void AppendEscaped(StringBuilder escaped, string part, string allowed) {
        for (int index = 0; index < part.Length; index++) {
            char character = part[index];
            if (character == '%' && index + 2 < part.Length && char.IsAsciiHexDigit(part[index + 1]) && char.IsAsciiHexDigit(part[index + 2])) {
                escaped.Append(part, index, 3);
                index += 2;
            } else if (char.IsAsciiLetterOrDigit(character) || allowed.Contains(character, StringComparison.Ordinal)) {
                escaped.Append(character);
            } else {
                int length = char.IsHighSurrogate(character) && index + 1 < part.Length && char.IsLowSurrogate(part[index + 1]) ? 2 : 1;
                foreach (byte value in Encoding.UTF8.GetBytes(part.Substring(index, length)))
                    escaped.Append('%').Append(Hex[value >> 4]).Append(Hex[value & 0xF]);
                index += length - 1;
            }
        }
    }

    #endregion
}
