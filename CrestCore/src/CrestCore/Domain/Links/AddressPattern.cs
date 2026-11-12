using System.Text;
using System.Text.RegularExpressions;

namespace CrestCore.Domain;

/// The addresses a network filter applies to, in the pattern syntax uBlock
/// Origin and AdGuard share: empty or `*` for every address; `||host` for a
/// host and its subdomains, from the start of a label, where a last label of
/// `.*` stands for any public suffix; `|` anchoring either end; `*` for any
/// run of characters; `^` for a separator or the end; and `/…/` for a
/// regular expression. A pattern is translated to a regular expression the
/// standard way; a host-anchored one checks its host first and matches the
/// rest of its pattern from where the host ends.
internal sealed class AddressPattern {
    #region Static Variables

    /// The pattern every address matches.
    public static readonly AddressPattern Everything = new(host: null, isEntity: false, rest: null);

    private const string HostAnchor = "||";

    /// What `^` stands for: one character that cannot be part of a host or
    /// a name, or the end of the address.
    private const string Separator = "(?:[^%.0-9A-Za-z_-]|$)";

    /// Where a pattern anchored at a host label may start when it spells no
    /// host to anchor at.
    private const string AnyLabel = @"^[a-z][a-z0-9+.-]*://(?:[^/?#]*\.)?";

    #endregion

    #region Variables

    /// For a pattern anchored at a host label: the host as it starts, in
    /// lowercase, without the `.*` of an entity.
    private readonly string? host;
    private readonly bool isEntity;
    /// The expression the address must match: for a host-anchored pattern,
    /// from where the host ends, or null when nothing follows it.
    private readonly FilterExpression? rest;

    #endregion

    #region Constructors

    private AddressPattern(string? host, bool isEntity, FilterExpression? rest) {
        this.host = host;
        this.isEntity = isEntity;
        this.rest = rest;
    }

    #endregion

    #region Actions - Reading

    /// The pattern `spelling` names, which minds letter case only when
    /// `matchCase`.
    public static AddressPattern Read(string spelling, bool matchCase) {
        ArgumentNullException.ThrowIfNull(spelling);
        if (spelling.Length == 0 || spelling == "*") return Everything;
        if (spelling.Length > 2 && spelling[0] == '/' && spelling[^1] == '/')
            return new(null, false, new(spelling[1..^1], matchCase));
        if (!spelling.StartsWith(HostAnchor, StringComparison.Ordinal)) {
            bool anchored = spelling[0] == '|';
            return new(null, false, new(Translated(anchored ? spelling[1..] : spelling, anchored ? "^" : ""), matchCase));
        }
        string anchoredRest = spelling[HostAnchor.Length..];
        int end = 0;
        while (end < anchoredRest.Length && (char.IsAsciiLetterOrDigit(anchoredRest[end]) || anchoredRest[end] is '.' or '-' or '_'))
            end++;
        if (end == 0) return new(null, false, new(Translated(anchoredRest, AnyLabel), matchCase));
        string name = anchoredRest[..end].ToLowerInvariant();
        bool entity = name.Length > 1 && name.EndsWith('.') && end < anchoredRest.Length && anchoredRest[end] == '*'
            && (end + 1 == anchoredRest.Length || anchoredRest[end + 1] is '^' or '/' or ':' or '?' or '|');
        string tail = anchoredRest[(entity ? end + 1 : end)..];
        return new(entity ? name[..^1] : name, entity, tail.Length == 0 ? null : new(Translated(tail, @"\G"), matchCase));
    }

    /// The expression the adblock pattern `body` translates to, after `start`.
    private static string Translated(string body, string start) {
        var translated = new StringBuilder(start);
        for (int index = 0; index < body.Length; index++) {
            char character = body[index];
            if (character == '*') translated.Append(".*");
            else if (character == '^') translated.Append(Separator);
            else if (character == '|' && index == body.Length - 1) translated.Append('$');
            else translated.Append(Regex.Escape(character.ToString()));
        }
        return translated.ToString();
    }

    #endregion

    #region Actions - Matching

    /// Whether `address` is one the pattern applies to.
    public bool Matches(LinkAddress address) {
        ArgumentNullException.ThrowIfNull(address);
        string location = address.Location;
        if (host is null) return rest is null || rest.Matches(location);
        for (int label = 0; label >= 0 && label < address.Host.Length; label = SiteDomain.NextLabel(address.Host, label)) {
            int start = address.HostStart + label;
            int end;
            if (isEntity) {
                if (!SiteDomain.EntityAt(location, start, address.HostEnd, host)) continue;
                end = address.HostEnd;
            } else {
                if (start + host.Length > location.Length || string.CompareOrdinal(location, start, host, 0, host.Length) != 0) continue;
                end = start + host.Length;
            }
            if (rest is null || rest.Matches(location, end)) return true;
        }
        return false;
    }

    #endregion
}
