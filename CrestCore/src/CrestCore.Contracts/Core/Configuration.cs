namespace CrestCore.Contracts;

/// Settings the host hands the core once: when it creates it, or when an
/// engine binding registers. A configuration is not a message: it has no wire
/// tag and is read only where it is expected.
public abstract record Configuration;
