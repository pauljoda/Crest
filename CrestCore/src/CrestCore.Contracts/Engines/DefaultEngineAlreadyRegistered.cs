namespace CrestCore.Contracts;

/// Another engine, `Current`, is already the one new pages open on.
public sealed record DefaultEngineAlreadyRegistered(EngineKind Current) : Rejection;
