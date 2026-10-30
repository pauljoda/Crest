namespace CrestCore.Contracts;

/// Whether Apple Passwords may be used for a launch, window and Space, or the
/// first reason it may not. A status travels as its index in `All`, so `All` is
/// append-only.
public sealed class ApplePasswordsStatus {
    #region Static Variables

    public static readonly ApplePasswordsStatus UnsupportedPlatform = new(name: "unsupported-platform", startsHelper: false, offersApplePasswords: false, needsPairing: false);
    public static readonly ApplePasswordsStatus IsolatedLaunch = new(name: "isolated-launch", startsHelper: false, offersApplePasswords: false, needsPairing: false);
    public static readonly ApplePasswordsStatus PrivateWindow = new(name: "private-window", startsHelper: false, offersApplePasswords: false, needsPairing: false);
    public static readonly ApplePasswordsStatus ManagedBrowserCapabilityRequired = new(name: "managed-browser-capability-required", startsHelper: false, offersApplePasswords: false, needsPairing: false);
    public static readonly ApplePasswordsStatus CredentialsDisabled = new(name: "credentials-disabled", startsHelper: false, offersApplePasswords: false, needsPairing: false);
    public static readonly ApplePasswordsStatus TurnedOff = new(name: "turned-off", startsHelper: false, offersApplePasswords: false, needsPairing: false);
    public static readonly ApplePasswordsStatus HelperUnavailable = new(name: "helper-unavailable", startsHelper: false, offersApplePasswords: false, needsPairing: false);
    public static readonly ApplePasswordsStatus HelperUnrecognized = new(name: "helper-unrecognized", startsHelper: false, offersApplePasswords: false, needsPairing: false);
    public static readonly ApplePasswordsStatus PairingRequired = new(name: "needs-pairing", startsHelper: true, offersApplePasswords: false, needsPairing: true);
    public static readonly ApplePasswordsStatus Available = new(name: "available", startsHelper: true, offersApplePasswords: true, needsPairing: false);

    public static IReadOnlyList<ApplePasswordsStatus> All { get; } = [
        UnsupportedPlatform, IsolatedLaunch, PrivateWindow, ManagedBrowserCapabilityRequired, CredentialsDisabled,
        TurnedOff, HelperUnavailable, HelperUnrecognized, PairingRequired, Available
    ];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether Crest may start the helper process.
    public bool StartsHelper { get; }

    /// Whether Apple Passwords rows may be offered to the person.
    public bool OffersApplePasswords { get; }

    /// Whether the person still has to pair Crest with Apple Passwords.
    public bool NeedsPairing { get; }

    #endregion

    #region Constructors

    private ApplePasswordsStatus(string name, bool startsHelper, bool offersApplePasswords, bool needsPairing) {
        Name = name;
        StartsHelper = startsHelper;
        OffersApplePasswords = offersApplePasswords;
        NeedsPairing = needsPairing;
    }

    #endregion

    #region Actions - Lookup

    public static ApplePasswordsStatus? Named(string? name) => All.FirstOrDefault(status => status.Name == name);

    #endregion
}
