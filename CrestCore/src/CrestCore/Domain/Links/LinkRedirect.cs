using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A link a site wraps around another to see it followed: a page at a known
/// path that only sends the reader on to the address one of its parameters
/// holds. A copied link stands for that destination instead.
internal sealed class LinkRedirect {
    #region Static Variables

    /// The most wrappers one link may be unwrapped from, so a chain of them
    /// ends.
    private const int MostUnwraps = 3;

    /// A path ending in it takes any path it starts.
    private const string AnyRest = "*";

    public static readonly LinkRedirect Google = new(["google.*"], "/url", ["q", "url"]);
    public static readonly LinkRedirect Facebook = new(["l.facebook.com", "lm.facebook.com"], "/l.php", ["u"]);
    public static readonly LinkRedirect Messenger = new(["l.messenger.com"], "/l.php", ["u"]);
    public static readonly LinkRedirect Instagram = new(["l.instagram.com"], "/", ["u"]);
    public static readonly LinkRedirect Reddit = new(["out.reddit.com"], "/*", ["url"]);
    public static readonly LinkRedirect YouTube = new(["youtube.com"], "/redirect", ["q"]);
    public static readonly LinkRedirect Slack = new(["slack-redir.net"], "/link", ["url"]);
    public static readonly LinkRedirect Steam = new(["steamcommunity.com"], "/linkfilter/", ["url", "u"]);
    public static readonly LinkRedirect VK = new(["vk.com"], "/away.php", ["to"]);
    public static readonly LinkRedirect LinkedIn = new(["linkedin.com"], "/redir/redirect", ["url"]);
    public static readonly LinkRedirect DuckDuckGo = new(["duckduckgo.com"], "/l/", ["uddg"]);
    public static readonly LinkRedirect Tumblr = new(["t.umblr.com"], "/redirect", ["z"]);

    public static IReadOnlyList<LinkRedirect> All { get; } =
        [Google, Facebook, Messenger, Instagram, Reddit, YouTube, Slack, Steam, VK, LinkedIn, DuckDuckGo, Tumblr];

    #endregion

    #region Variables

    /// The sites the wrapper runs on, each with every subdomain.
    private readonly IReadOnlyList<SiteDomain> sites;
    /// The wrapper's path, or how it starts when it ends in `*`.
    private readonly string path;
    /// The parameters that may hold the destination, in the order read.
    private readonly IReadOnlyList<string> parameters;

    #endregion

    #region Constructors

    private LinkRedirect(IReadOnlyList<string> sites, string path, IReadOnlyList<string> parameters) {
        this.sites = [.. sites.Select(site => new SiteDomain(site))];
        this.path = path;
        this.parameters = parameters;
    }

    #endregion

    #region Actions - Unwrapping

    /// The address `url` sends the reader to through as many wrappers as it
    /// is wrapped in, up to `MostUnwraps`, or `url` when no wrapper holds it.
    /// A destination is only ever an http or https address other than the
    /// wrapper's own.
    public static string Unwrapped(string url) {
        ArgumentNullException.ThrowIfNull(url);
        string current = url;
        for (int unwrap = 0; unwrap < MostUnwraps; unwrap++) {
            if (LinkAddress.Read(current) is not { } address) break;
            if (All.Select(redirect => redirect.Destination(address)).FirstOrDefault(destination => destination is not null)
                is not { } destination || destination == current)
                break;
            current = destination;
        }
        return current;
    }

    /// Where the wrapper at `address` sends the reader, or null when it is
    /// not one of this wrapper's pages or holds no web address.
    private string? Destination(LinkAddress address) {
        if (!sites.Any(site => site.Holds(address.Host))) return null;
        string pagePath = address.Path.Length == 0 ? "/" : address.Path;
        bool atPath = path.EndsWith(AnyRest, StringComparison.Ordinal)
            ? pagePath.StartsWith(path[..^AnyRest.Length], StringComparison.OrdinalIgnoreCase)
            : string.Equals(pagePath, path, StringComparison.OrdinalIgnoreCase);
        if (!atPath) return null;
        foreach (string name in parameters)
            foreach (var parameter in address.Parameters)
                if (parameter.Name == name && IsWebAddress(parameter.Value)) return parameter.Value;
        return null;
    }

    /// Whether `value` spells an http or https address with a host and no
    /// space or control character.
    private static bool IsWebAddress(string value) =>
        value.All(character => character > ' ' && character != '\u007f') && LinkAddress.Read(value) is not null;

    #endregion
}
