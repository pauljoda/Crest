namespace CrestCore.Contracts;

/// A binding for this engine is already registered.
public sealed record EngineAlreadyRegistered(EngineKind Kind) : Rejection;
