namespace CrestCore.Contracts;

/// How a status reads at a glance: settled, under way, needing the person, or
/// in trouble. A status that is none of these has no tone and stays in its
/// view's quiet style. Sets that report a status carry its tone, and each
/// platform draws a tone in one color, so the same status reads the same
/// everywhere. A tone travels as its index in `All`, so `All` is append-only.
public sealed class StatusTone {
    #region Static Variables

    /// Something is settled and fine: allowed, secure, ready.
    public static readonly StatusTone Success = new(name: "success");

    /// Something needs the person: a decision, a fix, or a caution to read.
    public static readonly StatusTone Warning = new(name: "warning");

    /// Something failed, was refused, is unsafe or was deleted.
    public static readonly StatusTone Danger = new(name: "danger");

    /// Something is under way, or happened without the person, and needs
    /// nothing from them.
    public static readonly StatusTone Info = new(name: "info");

    public static IReadOnlyList<StatusTone> All { get; } = [Success, Warning, Danger, Info];

    #endregion

    #region Variables

    public string Name { get; }

    #endregion

    #region Constructors

    private StatusTone(string name) {
        Name = name;
    }

    #endregion

    #region Actions - Lookup

    public static StatusTone? Named(string? name) => All.FirstOrDefault(tone => tone.Name == name);

    #endregion
}
