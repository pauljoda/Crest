namespace CrestCore.Contracts;

/// Closes a window. A saved window's record stays for the next launch; a
/// window that is not saved is gone. Closing a window that is not open
/// publishes nothing.
public sealed record CloseWindow(Guid WindowId) : WindowIntent;
