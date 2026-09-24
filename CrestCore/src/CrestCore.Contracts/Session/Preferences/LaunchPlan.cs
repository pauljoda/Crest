namespace CrestCore.Contracts;

/// How this launch treats the person's data and what its first window opens,
/// with the startup choice the persistent workspace keeps. First-run setup
/// that owns the first window is an active launch gate.
public sealed record LaunchPlan(Guid WorkspaceId, DevicePlatform Platform, LaunchEnvironment Environment, bool HasActiveLaunchGate)
    : Query<LaunchDecision>;
