namespace CrestCore.Contracts;

/// How far Crest trusts the connection of the document a page shows, and what
/// it tells the person about it. The core judges it from the facts the page's
/// engine reports (`PageSecurityFacts`), the same way on every engine: each
/// level says when it applies, and the first level in `Precedence` that
/// applies is the page's. A level travels as its index in `All`, so `All` is
/// append-only.
public sealed class PageSecurity {
    #region Static Variables

    /// Nothing to judge: no document yet, a local or internal page, a page on
    /// this device's own host, the engine's own error page, or a secure
    /// address whose connection the engine has not judged yet.
    public static readonly PageSecurity None = new(name: "none", title: "Not Secure", symbol: "lock.open.fill",
        applies: (facts, url) => facts.ErrorPage
            || (facts.CryptographicScheme ? !facts.ConnectionJudged : !facts.TravelsInPlainText(url)));

    /// A document delivered without transport security, such as plain HTTP
    /// from another host, or over a connection the engine warns about.
    public static readonly PageSecurity Insecure = new(name: "insecure", title: "Not Secure", symbol: "lock.open.fill",
        applies: (facts, _) => !facts.CryptographicScheme || facts.EngineWarns);

    /// A verified TLS connection with no insecure content.
    public static readonly PageSecurity Secure = new(name: "secure", title: "Secure", symbol: "lock.fill",
        applies: (_, _) => true, isSecure: true);

    /// A verified TLS connection whose document also shows or runs content
    /// that was not delivered securely.
    public static readonly PageSecurity MixedContent = new(name: "mixed_content", title: "Partly Secure",
        symbol: "lock.trianglebadge.exclamationmark.fill",
        applies: (facts, _) => facts.CryptographicScheme && facts.MixedContent != PageMixedContent.None,
        detail: "Some content on this page was not delivered securely.");

    /// The site's certificate is not trusted: the engine's warning page, or a
    /// page reached past it.
    public static readonly PageSecurity CertificateError = new(name: "certificate_error", title: "Certificate Not Trusted",
        symbol: "exclamationmark.lock.fill", applies: (facts, _) => facts.CertificateError,
        detail: "This site’s certificate is not trusted. Information you send could be read by others.", isHazardous: true);

    /// The engine flagged the page itself as malicious or deceptive.
    public static readonly PageSecurity Dangerous = new(name: "dangerous", title: "Dangerous Site",
        symbol: "exclamationmark.octagon.fill", applies: (facts, _) => facts.MaliciousContent,
        detail: "This site may try to harm your Mac or steal your information.", isHazardous: true);

    public static IReadOnlyList<PageSecurity> All { get; } = [None, Insecure, Secure, MixedContent, CertificateError, Dangerous];

    /// The order the levels are tried in: a malicious page outranks
    /// everything, a certificate error outranks what the connection carried,
    /// and only a connection with nothing against it is secure.
    private static IReadOnlyList<PageSecurity> Precedence { get; } = [Dangerous, CertificateError, None, MixedContent, Insecure, Secure];

    #endregion

    #region Variables

    /// The level's stored spelling.
    public string Name { get; }

    /// What the site controls call the connection.
    [Localized]
    public string Title { get; }

    /// The SF Symbol shown beside the title.
    public string Symbol { get; }

    /// What the site controls add about the connection, when there is more to
    /// say than its title.
    [Localized]
    public string? Detail { get; }

    /// A verified connection that delivered everything securely.
    public bool IsSecure { get; }

    /// The page may put the person at risk, beyond having no secure connection.
    public bool IsHazardous { get; }

    /// Whether the level describes the document at an address with these
    /// facts, once every level before it in `Precedence` did not.
    private readonly Func<PageSecurityFacts, string?, bool> applies;

    #endregion

    #region Constructors

    private PageSecurity(string name, string title, string symbol, Func<PageSecurityFacts, string?, bool> applies,
        string? detail = null, bool isSecure = false, bool isHazardous = false) {
        Name = name;
        Title = title;
        Symbol = symbol;
        Detail = detail;
        IsSecure = isSecure;
        IsHazardous = isHazardous;
        this.applies = applies;
    }

    #endregion

    #region Actions - Judging

    /// The level of the document at `url`, whose connection its engine's
    /// `facts` describe.
    internal static PageSecurity Judging(PageSecurityFacts facts, string? url) =>
        Precedence.First(level => level.applies(facts, url));

    #endregion

    #region Actions - Lookup

    public static PageSecurity? Named(string? name) => All.FirstOrDefault(security => security.Name == name);

    #endregion
}
