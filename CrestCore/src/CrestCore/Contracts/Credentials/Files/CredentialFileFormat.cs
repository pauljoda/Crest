namespace CrestCore.Contracts;

/// Which program wrote a password file, as its headers tell: each format but
/// a browser's own names headers that only its program writes together, and a
/// file naming none of them, Crest's own included, is a browser's own. A
/// format travels as its index in `All`, so `All` is append-only.
public sealed class CredentialFileFormat {
    #region Static Variables

    public static readonly CredentialFileFormat Browser = new(name: "browser", title: "Browser CSV", markers: [], precedence: 3);
    public static readonly CredentialFileFormat Firefox = new(name: "firefox", title: "Firefox CSV",
        markers: [["httprealm"], ["formactionorigin"], ["guid"]], precedence: 1);
    public static readonly CredentialFileFormat Safari = new(name: "safari", title: "Safari CSV",
        markers: [["title", "otpauth"], ["title", "otp_auth"]], precedence: 2);
    public static readonly CredentialFileFormat Bitwarden = new(name: "bitwarden", title: "Bitwarden CSV", markers: [["login_uri"]],
        precedence: 0);

    public static IReadOnlyList<CredentialFileFormat> All { get; } = [Browser, Firefox, Safari, Bitwarden];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the import review calls the file.
    [Localized]
    public string Title { get; }

    /// The sets of headers, as a file's headers read once normalized, that
    /// only this format writes together; a file naming every header of one
    /// set is this format. A format without any is the one a file is when no
    /// other format's set appears.
    private readonly IReadOnlyList<IReadOnlyList<string>> markers;
    /// Which format a file is taken for first when its headers name several:
    /// the lowest.
    private readonly int precedence;

    #endregion

    #region Constructors

    private CredentialFileFormat(string name, string title, IReadOnlyList<IReadOnlyList<string>> markers, int precedence) {
        Name = name;
        Title = title;
        this.markers = markers;
        this.precedence = precedence;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialFileFormat? Named(string? name) => All.FirstOrDefault(format => format.Name == name);

    /// The format a file whose normalized headers are `headers` is.
    public static CredentialFileFormat Detected(IReadOnlySet<string> headers) {
        ArgumentNullException.ThrowIfNull(headers);
        return All.OrderBy(format => format.precedence)
            .First(format => format.markers.Count == 0 || format.markers.Any(marker => marker.All(headers.Contains)));
    }

    #endregion
}
