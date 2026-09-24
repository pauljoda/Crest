namespace CrestCore.Contracts;

/// An intent about what one of this device's windows shows. The device owns
/// every window and what it shows; the session never holds any of it.
public abstract record WindowIntent : Intent;
