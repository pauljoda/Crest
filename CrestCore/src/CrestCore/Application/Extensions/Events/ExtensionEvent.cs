using CrestCore.Application;

namespace CrestCore.Contracts;

/// What an engine reports about the extensions of a profile, or about an
/// install the core asked of it. A report about an install the core no longer
/// runs, or that another engine runs, changes nothing.
public abstract record ExtensionEvent : EngineEvent {
    #region Abstract Methods

    /// Applies what `engine` reported to the app's extensions, publishing what
    /// it changed to `changes` and handing the commands it causes to `issue`.
    internal abstract void Apply(Extensions extensions, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue);

    #endregion

    #region Actions - Routing

    internal sealed override void Route(CrestApp app, Engine engine, ChangeFeed changes) =>
        app.Extensions.Report(this, engine, changes, app.Issue);

    #endregion
}
