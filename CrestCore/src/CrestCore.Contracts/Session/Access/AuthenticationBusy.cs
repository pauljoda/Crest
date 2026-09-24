namespace CrestCore.Contracts;

/// Another request to unlock a Space is waiting on the device owner.
public sealed record AuthenticationBusy() : Rejection;
