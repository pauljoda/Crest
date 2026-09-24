namespace CrestCore.Contracts;

/// An open window shows something else: it opened, a person chose what it
/// shows, or the session changed under it and the core repaired it.
public sealed record WindowChanged(WindowState Window) : Change;
