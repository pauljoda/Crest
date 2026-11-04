using CrestCore.Application;

namespace CrestCore.Contracts;

/// A request about the extensions of one of the person's Spaces, or an
/// install of one, which the core checks against the Space before any engine
/// hears of it. Never saved or synced.
public abstract record ExtensionIntent : Intent {
    #region Abstract Methods

    /// Runs the intent in the app's extensions, publishing what it changed to
    /// `changes` and handing the engine commands it causes to `issue`.
    internal abstract void Apply(Extensions extensions, ChangeFeed changes, Action<Engine, EngineCommand> issue);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Extensions.Handle(this, changes, app.Issue));

    #endregion
}
