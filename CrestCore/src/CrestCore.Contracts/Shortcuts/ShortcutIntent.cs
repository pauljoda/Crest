namespace CrestCore.Contracts;

/// An intent about this device's shortcut choices. The device store keeps
/// them beside the session, never in it, and they never sync. Only the
/// commands this device offers, those its default engine can perform, hold or
/// lose a chord.
public abstract record ShortcutIntent : Intent;
