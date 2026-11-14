using System.Text;

namespace CrestCore.Domain;

/// One `$removeparam` filter, in the syntax uBlock Origin and AdGuard share,
/// read for an address a person copies: a page loaded as a top-level
/// document, first-party to itself, whose own host is the source a
/// `domain=` option names. A filter that could never apply to such an
/// address, such as one only for scripts or for third-party loads, or one
/// with an option this reader does not know, is not read at all.
internal sealed class ParameterFilter {
    #region Types

    /// What a filter's options say as they are read.
    private sealed class Reading {
        public bool RemovesParameters;
        public string? Parameter;
        public readonly List<SiteDomain> Domains = [];
        public readonly List<SiteDomain> ExcludedDomains = [];
        public bool MatchesCase;
        /// Whether an option names kinds of load, and whether a top-level
        /// document is among them or excluded from them.
        public bool NamesKinds;
        public bool NamesDocuments;
        public bool ExcludesDocuments;
    }

    /// An option a filter may carry, under each of its spellings, and what it
    /// does to the filter as it is read: `read` takes the reading, whether the
    /// option was negated with `~`, and its value, and answers whether the
    /// filter can still apply to a copied address.
    private sealed class Option {
        #region Static Variables

        public static readonly Option RemovesParameters = new(["removeparam", "queryprune"], (reading, negated, value) => {
            if (negated || value is { Length: 0 }) return false;
            reading.RemovesParameters = true;
            reading.Parameter = value;
            return true;
        });

        public static readonly Option Domain = new(["domain", "from"], (reading, negated, value) => {
            if (negated || string.IsNullOrEmpty(value)) return false;
            foreach (string entry in value.Split('|')) {
                bool excluded = entry.StartsWith('~');
                string name = excluded ? entry[1..] : entry;
                // A domain spelled as a regular expression is not read.
                if (name.Length == 0 || name.Contains('/', StringComparison.Ordinal)) return false;
                (excluded ? reading.ExcludedDomains : reading.Domains).Add(new(name));
            }
            return true;
        });

        public static readonly Option Document = new(["document", "doc", "main_frame"], (reading, negated, value) => {
            if (value is not null) return false;
            if (negated) reading.ExcludesDocuments = true;
            else reading.NamesKinds = reading.NamesDocuments = true;
            return true;
        });

        /// Every other kind of load: naming one limits the filter to it, and
        /// excluding one leaves documents in.
        public static readonly Option OtherKind = new([
            "script", "image", "stylesheet", "css", "font", "media", "object", "subdocument", "frame", "xhr", "xmlhttprequest",
            "ping", "beacon", "websocket", "webrtc", "other", "popup", "object-subrequest", "fetch"
        ], (reading, negated, value) => {
            if (value is not null) return false;
            if (!negated) reading.NamesKinds = true;
            return true;
        });

        /// A copied address is its own first party: a filter only for
        /// third-party loads never applies, and one only for first-party
        /// loads always does.
        public static readonly Option ThirdParty = new(["third-party", "3p"], (_, negated, value) => value is null && negated);

        public static readonly Option FirstParty = new(["first-party", "1p"], (_, negated, value) => value is null && !negated);

        public static readonly Option MatchCase = new(["match-case"], (reading, negated, value) => {
            reading.MatchesCase = true;
            return !negated && value is null;
        });

        /// Lets a filter outrank exceptions in a blocker; a copied address
        /// reads every exception alike.
        public static readonly Option Important = new(["important"], (_, negated, value) => !negated && value is null);

        public static IReadOnlyList<Option> All { get; } =
            [RemovesParameters, Domain, Document, OtherKind, ThirdParty, FirstParty, MatchCase, Important];

        #endregion

        #region Variables

        private readonly IReadOnlyList<string> spellings;
        private readonly Func<Reading, bool, string?, bool> read;

        #endregion

        #region Constructors

        private Option(IReadOnlyList<string> spellings, Func<Reading, bool, string?, bool> read) {
            this.spellings = spellings;
            this.read = read;
        }

        #endregion

        #region Actions - Reading

        public static Option? Spelled(string name) => All.FirstOrDefault(option => option.spellings.Contains(name));

        public bool Read(Reading reading, bool negated, string? value) => read(reading, negated, value);

        #endregion
    }

    #endregion

    #region Static Variables

    private const string ExceptionMarker = "@@";
    private const char OptionsMarker = '$';
    private const string BadFilter = "badfilter";

    /// How element-hiding and scriptlet filters set themselves apart.
    private static readonly string[] CosmeticMarkers = ["##", "#@#", "#$#", "#%#", "#?#"];

    #endregion

    #region Variables

    /// The filter as written, without a `badfilter` option, which a
    /// `badfilter` filter spelled alike cancels.
    public string Spelling { get; }

    /// Whether the filter keeps the parameters it names, which other filters
    /// would remove.
    public bool IsException { get; }

    /// Whether it is a `badfilter` filter, which cancels the filter spelled
    /// `Spelling` in every list and applies to nothing itself.
    public bool Cancels { get; }

    /// Whether it names every parameter: an exception that does turns
    /// removal off where it applies.
    public bool NamesEverything => parameterName is null && parameterExpression is null;

    private readonly AddressPattern pattern;
    private readonly IReadOnlyList<SiteDomain> domains;
    private readonly IReadOnlyList<SiteDomain> excludedDomains;
    /// The one name the filter names, decoded as a parameter's name is, since
    /// lists spell special characters in a name percent-encoded; or the
    /// expression `name=value` must match; neither for every parameter.
    /// Inverted, the filter names every parameter but those.
    private readonly string? parameterName;
    private readonly FilterExpression? parameterExpression;
    private readonly bool inverted;

    #endregion

    #region Constructors

    private ParameterFilter(string spelling, bool isException, bool cancels, AddressPattern pattern,
        IReadOnlyList<SiteDomain> domains, IReadOnlyList<SiteDomain> excludedDomains, string? parameterName,
        FilterExpression? parameterExpression, bool inverted) {
        Spelling = spelling;
        IsException = isException;
        Cancels = cancels;
        this.pattern = pattern;
        this.domains = domains;
        this.excludedDomains = excludedDomains;
        this.parameterName = parameterName is null ? null : Uri.UnescapeDataString(parameterName);
        this.parameterExpression = parameterExpression;
        this.inverted = inverted;
    }

    #endregion

    #region Actions - Reading

    /// The filter a list's `line` spells, or null for a comment, a cosmetic
    /// filter, a network filter without `removeparam`, or one that could never
    /// apply to a copied address.
    public static ParameterFilter? Read(string line) {
        ArgumentNullException.ThrowIfNull(line);
        string rule = line.Trim();
        if (rule.Length == 0 || rule[0] is '!' or '[' || CosmeticMarkers.Any(marker => rule.Contains(marker, StringComparison.Ordinal)))
            return null;
        bool isException = rule.StartsWith(ExceptionMarker, StringComparison.Ordinal);
        string body = isException ? rule[ExceptionMarker.Length..] : rule;
        int anchor = OptionsAnchor(body);
        if (anchor < 0) return null;
        string patternSpelling = body[..anchor];
        var options = Options(body[(anchor + 1)..]);
        if (options.Contains(BadFilter)) {
            string cancelled = $"{(isException ? ExceptionMarker : "")}{patternSpelling}{OptionsMarker}"
                + string.Join(',', options.Where(option => option != BadFilter));
            return new(cancelled, isException, cancels: true, AddressPattern.Everything, [], [], null, null, false);
        }
        var reading = new Reading();
        foreach (string option in options) {
            bool negated = option.StartsWith('~');
            int equals = option.IndexOf('=', StringComparison.Ordinal);
            string name = option[(negated ? 1 : 0)..(equals < 0 ? option.Length : equals)];
            string? value = equals < 0 ? null : option[(equals + 1)..].Replace("\\,", ",", StringComparison.Ordinal);
            if (Option.Spelled(name) is not { } known || !known.Read(reading, negated, value)) return null;
        }
        if (!reading.RemovesParameters || reading.ExcludesDocuments || (reading.NamesKinds && !reading.NamesDocuments)) return null;
        string? parameter = reading.Parameter;
        bool inverted = parameter is not null && parameter.StartsWith('~');
        if (inverted) parameter = parameter![1..];
        if (parameter is { Length: 0 }) return null;
        FilterExpression? expression = null;
        if (parameter is not null && parameter.Length > 2 && parameter[0] == '/' && parameter.LastIndexOf('/') > 0) {
            int close = parameter.LastIndexOf('/');
            string flags = parameter[(close + 1)..];
            if (flags.Any(flag => flag != 'i')) return null;
            expression = new(parameter[1..close], matchCase: flags.Length == 0);
            parameter = null;
        }
        return new(rule, isException, cancels: false, AddressPattern.Read(patternSpelling, reading.MatchesCase),
            reading.Domains, reading.ExcludedDomains, parameter, expression, inverted);
    }

    /// Where `body`'s options start: the first `$` followed by an option's
    /// name and then `=`, `,` or the end, so a `$` in a pattern or in a
    /// regular expression's value is not taken for it; -1 for none.
    private static int OptionsAnchor(string body) {
        for (int index = body.IndexOf(OptionsMarker); index >= 0; index = body.IndexOf(OptionsMarker, index + 1)) {
            int start = index + 1;
            if (start < body.Length && body[start] == '~') start++;
            int end = start;
            while (end < body.Length && (char.IsAsciiLetterOrDigit(body[end]) || body[end] is '_' or '-')) end++;
            if (end > start && (end == body.Length || body[end] is '=' or ',')) return index;
        }
        return -1;
    }

    /// The options `text` lists, split at each comma a backslash does not
    /// escape.
    private static List<string> Options(string text) {
        var options = new List<string>();
        var option = new StringBuilder();
        for (int index = 0; index < text.Length; index++) {
            if (text[index] == '\\' && index + 1 < text.Length) {
                option.Append(text, index, 2);
                index++;
            } else if (text[index] == ',') {
                options.Add(option.ToString());
                option.Clear();
            } else {
                option.Append(text[index]);
            }
        }
        options.Add(option.ToString());
        return options;
    }

    #endregion

    #region Actions - Applying

    /// Whether the filter applies to `address`: its pattern matches it, and
    /// its host is one of the domains the filter is limited to and none it is
    /// kept from.
    public bool Applies(LinkAddress address) {
        ArgumentNullException.ThrowIfNull(address);
        if (Cancels) return false;
        if (domains.Count > 0 && !domains.Any(domain => domain.Holds(address.Host))) return false;
        if (excludedDomains.Any(domain => domain.Holds(address.Host))) return false;
        return pattern.Matches(address);
    }

    /// Whether the filter names `parameter`: the filter removes it, or, for an
    /// exception, keeps it. An expression that does not read names nothing,
    /// inverted or not.
    public bool Names(QueryParameter parameter) {
        ArgumentNullException.ThrowIfNull(parameter);
        if (parameterExpression is not null && !parameterExpression.IsReadable) return false;
        bool named = parameterName is not null ? parameter.Name == parameterName
            : parameterExpression is null || parameterExpression.Matches(parameter.Pair);
        return named != inverted;
    }

    #endregion
}
