using CrestCore.Contracts;

namespace CrestCore.Application;

/// One registered engine binding: which engine it is, whether new pages open
/// on it, and how the core hands it a command. A retired engine takes no more
/// commands, including ones issued before it was retired.
public sealed class Engine {
    #region Variables

    public EngineKind Kind { get; }

    /// New pages open on this engine.
    public bool IsDefault { get; }

    private readonly Action<EngineCommand> run;
    private volatile bool isRetired;

    #endregion

    #region Constructors

    internal Engine(EngineRegistration registration, Action<EngineCommand> run) {
        Kind = registration.Kind;
        IsDefault = registration.IsDefault;
        this.run = run;
    }

    #endregion

    #region Actions - Commands

    /// Hands the binding one command, unless the engine has been retired.
    internal void Run(EngineCommand command) {
        if (!isRetired) run(command);
    }

    /// Stops every later command from reaching the binding.
    internal void Retire() => isRetired = true;

    #endregion
}
