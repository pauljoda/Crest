namespace CrestCore.Contracts;

/// Why one row of a password file is left out while the rest import: the
/// column whose field keeps it out, or null for the row as a whole, and what
/// the person is told. A flaw travels as its index in `All`, so `All` is
/// append-only.
public sealed class CredentialRowFlaw {
    #region Static Variables

    public static readonly CredentialRowFlaw InvalidOrigin = new(name: "invalidOrigin", column: CredentialFileColumn.Site,
        message: "The site is not a valid web address.");
    public static readonly CredentialRowFlaw EmptyPassword = new(name: "emptyPassword", column: CredentialFileColumn.Password,
        message: "The password is empty.");
    public static readonly CredentialRowFlaw MalformedRow = new(name: "malformedRow", column: null,
        message: "The row does not match the detected columns.");
    public static readonly CredentialRowFlaw NoSite = new(name: "noSite", column: CredentialFileColumn.Site, message: "The site is empty.");
    /// The site names an address of another kind than a web page's, such as
    /// an app's.
    public static readonly CredentialRowFlaw NotWebAddress = new(name: "notWebAddress", column: CredentialFileColumn.Site,
        message: "The site is not an http or https address.");
    public static readonly CredentialRowFlaw NotIPv6Address = new(name: "notIPv6Address", column: CredentialFileColumn.Site,
        message: "The site’s address in brackets is not an IPv6 address.");
    /// The site's IPv6 address names a network interface, which a page's
    /// address never does, so its password could never fill.
    public static readonly CredentialRowFlaw ZoneIdentifier = new(name: "zoneIdentifier", column: CredentialFileColumn.Site,
        message: "The site’s IPv6 address names a network interface, which a web page’s address never does.");
    /// The site's host ends in a number, so it must be an IPv4 address, and
    /// it is none.
    public static readonly CredentialRowFlaw NotIPv4Address = new(name: "notIPv4Address", column: CredentialFileColumn.Site,
        message: "The site’s IP address is not a valid IPv4 address.");
    /// The site's name mixes right-to-left and left-to-right text in a way
    /// IDNA's bidi rule refuses, so no page can have it.
    public static readonly CredentialRowFlaw MixedDirectionName = new(name: "mixedDirectionName", column: CredentialFileColumn.Site,
        message: "The site’s name mixes right-to-left and left-to-right text in a way web addresses don’t allow.");
    public static readonly CredentialRowFlaw InvalidPort = new(name: "invalidPort", column: CredentialFileColumn.Site,
        message: "The site’s port is not a number from 1 to 65535.");

    public static IReadOnlyList<CredentialRowFlaw> All { get; } = [InvalidOrigin, EmptyPassword, MalformedRow, NoSite, NotWebAddress,
        NotIPv6Address, ZoneIdentifier, NotIPv4Address, MixedDirectionName, InvalidPort];

    #endregion

    #region Variables

    public string Name { get; }

    /// The column whose field keeps the row out, or null for a row that does
    /// not fit the file's columns at all.
    public CredentialFileColumn? Column { get; }

    /// What the person is told.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private CredentialRowFlaw(string name, CredentialFileColumn? column, string message) {
        Name = name;
        Column = column;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialRowFlaw? Named(string? name) => All.FirstOrDefault(flaw => flaw.Name == name);

    #endregion
}
