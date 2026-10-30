namespace CrestCore.Contracts;

/// What the app knows about the Apple Passwords helper this launch. A fact
/// travels as its index in `All`, so `All` is append-only.
public sealed class ApplePasswordsHelperFact {
    #region Static Variables

    /// The helper has not been started yet.
    public static readonly ApplePasswordsHelperFact NotStarted = new(name: "not-started", status: ApplePasswordsStatus.PairingRequired);
    /// The helper runs and the person has not paired Crest with it.
    public static readonly ApplePasswordsHelperFact Unpaired = new(name: "unpaired", status: ApplePasswordsStatus.PairingRequired);
    /// The helper runs and Crest is paired with it.
    public static readonly ApplePasswordsHelperFact Paired = new(name: "paired", status: ApplePasswordsStatus.Available);
    /// The helper is missing, was killed by the kernel or its pipe broke.
    public static readonly ApplePasswordsHelperFact Unavailable = new(name: "unavailable", status: ApplePasswordsStatus.HelperUnavailable);
    /// The helper's capabilities lack SRP with RFC verification, or hold a value the client cannot decode.
    public static readonly ApplePasswordsHelperFact Unrecognized = new(name: "unrecognized", status: ApplePasswordsStatus.HelperUnrecognized);

    public static IReadOnlyList<ApplePasswordsHelperFact> All { get; } = [NotStarted, Unpaired, Paired, Unavailable, Unrecognized];

    #endregion

    #region Variables

    public string Name { get; }

    /// The status once every launch fact allows Apple Passwords.
    public ApplePasswordsStatus Status { get; }

    #endregion

    #region Constructors

    private ApplePasswordsHelperFact(string name, ApplePasswordsStatus status) {
        Name = name;
        Status = status;
    }

    #endregion

    #region Actions - Lookup

    public static ApplePasswordsHelperFact? Named(string? name) => All.FirstOrDefault(fact => fact.Name == name);

    #endregion
}
