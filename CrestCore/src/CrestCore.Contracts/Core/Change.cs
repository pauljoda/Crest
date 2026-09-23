namespace CrestCore.Contracts;

/// What an intent changed. A change carries the resulting values, never an
/// instruction the caller has to work out again.
public abstract record Change;
