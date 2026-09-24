namespace CrestCore.Contracts;

/// Whether this launch may offer saved passwords to the system's Passwords app,
/// or why not.
public sealed record SystemPasswordWriteThroughSupport(SystemPasswordWriteThroughAvailability Availability);
