namespace CrestCore.Contracts;

/// No registered engine can host a new page: none is the default.
public sealed record EngineNotRegistered : Rejection;
