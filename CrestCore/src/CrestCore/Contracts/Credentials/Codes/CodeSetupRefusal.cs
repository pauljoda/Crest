namespace CrestCore.Contracts;

/// Why text doesn't set up one-time codes, with what the person is told. A
/// refusal travels as its index in `All`, so `All` is append-only.
public sealed class CodeSetupRefusal {
    #region Static Variables

    /// The text is neither a setup key nor a link that holds one.
    public static readonly CodeSetupRefusal NotASetup = new(name: "notASetup", message: "This isn’t a setup key.");
    /// The link sets up codes that count uses (`otpauth://hotp`), not time.
    public static readonly CodeSetupRefusal CounterBased = new(name: "counterBased",
        message: "Crest doesn’t support counter-based codes.");
    /// The link names an algorithm or encoder Crest doesn't make codes with.
    public static readonly CodeSetupRefusal UnsupportedAlgorithm = new(name: "unsupportedAlgorithm",
        message: "Crest doesn’t support this setup key’s algorithm.");
    /// The key holds fewer than 10 bytes.
    public static readonly CodeSetupRefusal SecretTooShort = new(name: "secretTooShort", message: "This setup key is too short.");
    /// The key is missing, isn't base32, or holds more than 128 bytes.
    public static readonly CodeSetupRefusal InvalidSecret = new(name: "invalidSecret", message: "This setup key isn’t valid.");
    /// The code's length is outside what its style allows.
    public static readonly CodeSetupRefusal InvalidDigits = new(name: "invalidDigits", message: "Crest doesn’t support this code length.");
    /// The code's period is outside what its style allows.
    public static readonly CodeSetupRefusal InvalidPeriod = new(name: "invalidPeriod",
        message: "Crest doesn’t support this code interval.");

    public static IReadOnlyList<CodeSetupRefusal> All { get; } = [NotASetup, CounterBased, UnsupportedAlgorithm, SecretTooShort,
        InvalidSecret, InvalidDigits, InvalidPeriod];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the person is told.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private CodeSetupRefusal(string name, string message) {
        Name = name;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static CodeSetupRefusal? Named(string? name) => All.FirstOrDefault(refusal => refusal.Name == name);

    #endregion
}
