namespace CrestCore.Contracts;

/// The engine does not support `Capability`, which every engine must support
/// to register.
public sealed record EngineLacksCapability(EngineKind Kind, EngineCapability Capability) : Rejection;
