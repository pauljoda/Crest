namespace CrestCore.Contracts;

/// A scheme the web serves pages over, with the port a URL of the scheme means
/// when it names none. An origin of any other scheme keeps the port it was
/// given. A scheme travels as its index in `All`, so `All` is append-only.
public sealed class WebScheme {
    #region Static Variables

    public static readonly WebScheme Http = new(name: "http", defaultPort: 80);
    public static readonly WebScheme Https = new(name: "https", defaultPort: 443);

    public static IReadOnlyList<WebScheme> All { get; } = [Http, Https];

    #endregion

    #region Variables

    /// The scheme as a URL spells it, in lowercase.
    public string Name { get; }

    /// The port a URL of the scheme means when it names none.
    public int DefaultPort { get; }

    #endregion

    #region Constructors

    private WebScheme(string name, int defaultPort) {
        Name = name;
        DefaultPort = defaultPort;
    }

    #endregion

    #region Actions - Lookup

    public static WebScheme? Named(string? name) => All.FirstOrDefault(scheme => scheme.Name == name);

    #endregion
}
