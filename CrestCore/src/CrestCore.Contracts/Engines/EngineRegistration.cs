namespace CrestCore.Contracts;

/// What an engine binding tells the core once, when it registers: which engine
/// it is, the capabilities it supports, and whether new pages open on it. It
/// must support every required capability, one engine is the default, and each
/// kind registers once.
public sealed record EngineRegistration(EngineKind Kind, IReadOnlyList<EngineCapability> Capabilities, bool IsDefault)
    : Configuration;
