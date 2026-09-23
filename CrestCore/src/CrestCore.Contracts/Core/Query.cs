namespace CrestCore.Contracts;

/// A question the core answers with a `TAnswer` without changing any state.
public abstract record Query<TAnswer>;
