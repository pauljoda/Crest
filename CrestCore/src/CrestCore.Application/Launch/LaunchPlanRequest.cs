using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A `launch.plan` policy request: the flags the platform parsed from its own
/// environment, its device platform and whether a launch gate is active.
internal sealed record LaunchPlanRequest(LaunchEnvironment Environment, DevicePlatform Platform, bool HasActiveLaunchGate) {
    #region Actions - Decoding

    public static LaunchPlanRequest Decode(JsonElement request) {
        Protocol.Members(request, LaunchCodes.RequestMembers);
        var environment = LaunchCodes.Environment(request.GetProperty("environment"));
        var platform = DeviceCodes.Platform(request);
        return new(environment, platform, PolicyFields.Flag(request, "hasActiveLaunchGate"));
    }

    #endregion

    #region Actions - Planning

    /// The plan for this launch, before any session supplies its saved startup
    /// preference; the `LaunchPlan` query supplies it.
    public LaunchDecision Plan(StartupBehavior? storedStartup) =>
        LaunchPolicy.Plan(Environment, Platform, storedStartup, HasActiveLaunchGate);

    #endregion
}
