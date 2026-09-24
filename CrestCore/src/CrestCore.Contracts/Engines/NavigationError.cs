namespace CrestCore.Contracts;

/// Why a page's navigation failed, as either engine reports it. `Code` is the
/// stable spelling the failure page shows, so a report names the same
/// problem whichever engine saw it. An error travels as its index in `All`,
/// so `All` is append-only.
public sealed class NavigationError {
    #region Variables

    public static readonly NavigationError Offline = new(name: "offline", code: "CREST_INTERNET_DISCONNECTED");
    public static readonly NavigationError TimedOut = new(name: "timedOut", code: "CREST_TIMED_OUT");
    public static readonly NavigationError CannotFindServer = new(name: "cannotFindServer", code: "CREST_NAME_NOT_RESOLVED");
    public static readonly NavigationError CannotConnect = new(name: "cannotConnect", code: "CREST_CONNECTION_REFUSED");
    public static readonly NavigationError ConnectionLost = new(name: "connectionLost", code: "CREST_CONNECTION_RESET");
    public static readonly NavigationError SecureConnectionFailed = new(name: "secureConnectionFailed", code: "CREST_CERTIFICATE_INVALID");
    public static readonly NavigationError TooManyRedirects = new(name: "tooManyRedirects", code: "CREST_TOO_MANY_REDIRECTS");
    public static readonly NavigationError UnsupportedAddress = new(name: "unsupportedAddress", code: "CREST_UNSUPPORTED_ADDRESS");
    public static readonly NavigationError Blocked = new(name: "blocked", code: "CREST_CONTENT_BLOCKED");
    public static readonly NavigationError Unavailable = new(name: "unavailable", code: "CREST_RESOURCE_UNAVAILABLE");
    public static readonly NavigationError WebContentProcessStopped = new(name: "webContentProcessStopped", code: "CREST_WEB_PROCESS_STOPPED");
    public static readonly NavigationError Unknown = new(name: "unknown", code: "CREST_NAVIGATION_FAILED");

    public static IReadOnlyList<NavigationError> All { get; } = [
        Offline, TimedOut, CannotFindServer, CannotConnect, ConnectionLost, SecureConnectionFailed, TooManyRedirects,
        UnsupportedAddress, Blocked, Unavailable, WebContentProcessStopped, Unknown
    ];

    public string Name { get; }

    /// The error code the failure page shows and a support request quotes.
    public string Code { get; }

    #endregion

    #region Constructors

    private NavigationError(string name, string code) {
        Name = name;
        Code = code;
    }

    #endregion

    #region Actions - Lookup

    public static NavigationError? Named(string? name) => All.FirstOrDefault(error => error.Name == name);

    #endregion
}
