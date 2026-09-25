using CrestCore.Contracts;

namespace CrestCore.Application;

/// The engine bindings this core hosts pages on, by kind. One of them is the
/// default, which new pages open on. Never saved or synced: a composition
/// registers what it carries every time it starts.
internal sealed class Engines {
    #region Variables

    private readonly Dictionary<EngineKind, Engine> registered = [];

    /// The engine new pages open on, or null while none is registered.
    public Engine? Default => registered.Values.FirstOrDefault(engine => engine.IsDefault);

    /// The commands this device offers, in catalog order: those whose whole
    /// feature the default engine supports, or every command before one registers.
    public IReadOnlyList<ShortcutCommand> OfferedCommands() =>
        Default is { } engine ? [.. ShortcutCommand.All.Where(command => command.IsOffered(engine.Supports))] : ShortcutCommand.All;

    #endregion

    #region Actions - Registration

    /// Registers a binding that supports every required capability, as the
    /// default only when no other engine is. Throws `Rejected` naming the rule
    /// it breaks.
    public Engine Register(EngineRegistration registration, Action<EngineCommand> run) {
        ArgumentNullException.ThrowIfNull(registration);
        ArgumentNullException.ThrowIfNull(run);
        if (EngineCapability.Required.FirstOrDefault(capability => !registration.Capabilities.Contains(capability)) is { } missing)
            throw new Rejected(new EngineLacksCapability(registration.Kind, missing));
        if (registered.ContainsKey(registration.Kind)) throw new Rejected(new EngineAlreadyRegistered(registration.Kind));
        if (registration.IsDefault && Default is { } existing) throw new Rejected(new DefaultEngineAlreadyRegistered(existing.Kind));
        var engine = new Engine(registration, run);
        registered[engine.Kind] = engine;
        return engine;
    }

    /// Removes a binding, which takes no more commands. Its pages stay until
    /// their owners release them.
    public void Unregister(Engine engine) {
        ArgumentNullException.ThrowIfNull(engine);
        if (registered.TryGetValue(engine.Kind, out var current) && ReferenceEquals(current, engine)) registered.Remove(engine.Kind);
        engine.Retire();
    }

    /// Retires every binding: the core is going away.
    public void Clear() {
        foreach (var engine in registered.Values) engine.Retire();
        registered.Clear();
    }

    #endregion
}
