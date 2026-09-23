namespace CrestCore.Contracts;

/// A request to change the core's state. The core answers it with the changes
/// it caused, or refuses it with one rejection.
public abstract record Intent;
