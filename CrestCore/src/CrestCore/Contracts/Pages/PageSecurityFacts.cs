namespace CrestCore.Contracts;

/// What a page's engine knows about the connection of the document it shows,
/// which the core judges as the page's `PageSecurity`. Each engine reports
/// what it can see and leaves false what it cannot: whether the document's
/// scheme is cryptographic, whether the engine has judged its connection yet,
/// whether the site's certificate failed (and stays failed once the person
/// went past the engine's warning), whether the engine warns about the scheme
/// or the connection itself, what insecure content the document took, whether
/// the engine flags the page as malicious, and whether it shows the engine's
/// own error page.
public sealed record PageSecurityFacts(bool CryptographicScheme, bool ConnectionJudged, bool CertificateError,
    bool EngineWarns, PageMixedContent MixedContent, bool MaliciousContent, bool ErrorPage) {
    #region Static Variables

    /// A page its engine shows no document in yet: nothing is known.
    public static PageSecurityFacts Unknown { get; } = new(CryptographicScheme: false, ConnectionJudged: false,
        CertificateError: false, EngineWarns: false, PageMixedContent.None, MaliciousContent: false, ErrorPage: false);

    #endregion

    #region Actions - Judging

    /// Whether the document at `url` came over the network without
    /// encryption: the engine warns about its plain scheme, or it is a web
    /// address on a host other than this device's own.
    internal bool TravelsInPlainText(string? url) =>
        !CryptographicScheme && (EngineWarns || url is { } address && new WebAddress(address).Origin is { IsLoopback: false });

    #endregion
}
