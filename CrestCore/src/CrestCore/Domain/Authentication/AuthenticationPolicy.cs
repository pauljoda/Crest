using CrestCore.Contracts;

namespace CrestCore.Domain;

/// HTTP authentication rules: which challenges Crest prompts for and how the
/// prompt names the server asking.
public static class AuthenticationPolicy {
    #region Variables

    public const int MaximumCredentialAttempts = 3;

    #endregion

    #region Actions - Challenges

    /// Proxy and non-HTTP challenges keep the system's handling. Basic and
    /// Digest prompt until the server has refused three attempts, then cancel.
    public static AuthenticationHandling Handling(AuthenticationMethod method, bool isProxy, int previousFailureCount) {
        ArgumentNullException.ThrowIfNull(method);
        if (isProxy || !method.PromptsForCredentials) return AuthenticationHandling.PerformDefaultHandling;
        return previousFailureCount < MaximumCredentialAttempts
            ? AuthenticationHandling.PromptForCredentials : AuthenticationHandling.Cancel;
    }

    /// The server as the prompt names it: the host, with the port only when it
    /// is not the scheme's default. Null when the challenge has no host; the
    /// platform then names Crest itself.
    public static string? SourceLabel(string host, int port, string? scheme) {
        ArgumentNullException.ThrowIfNull(host);
        if (host.Length == 0) return null;
        return WebScheme.Spelled(scheme)?.DefaultPort == port ? host : $"{host}:{port}";
    }

    #endregion
}
