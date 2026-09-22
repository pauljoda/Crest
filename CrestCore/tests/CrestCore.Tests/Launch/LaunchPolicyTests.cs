using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class LaunchPolicyTests {
    private static readonly string[] FixtureFlags = [
        "testRuntime", "previewRuntime", "isolatedSession", "isolatedCloudSync", "resetSession", "showcase",
        "inMemoryCredentials", "onboardingWelcome", "desktopSetup", "mobileSetup", "performanceHarness", "updateTestFeed"
    ];

    private static JsonObject Environment(params string[] enabled) {
        var value = new JsonObject();
        foreach (var flag in FixtureFlags.Append("namedProfile")) value[flag] = enabled.Contains(flag);
        return value;
    }

    private static JsonNode Plan(JsonObject environment, string platform = "desktop", string? stored = null, bool gate = false) =>
        JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "launch.plan",
            ["platform"] = platform,
            ["environment"] = environment,
            ["storedStartupBehavior"] = stored,
            ["hasActiveLaunchGate"] = gate
        }.ToJsonString())))!;

    [Fact]
    public void EveryTestFixtureAndHarnessLaunchStaysOutOfTheInstalledProfile() {
        foreach (var flag in FixtureFlags)
            Assert.True(Plan(Environment(flag))["requiresIsolation"]!.GetValue<bool>(), flag);
        var installed = Plan(Environment());
        Assert.False(installed["requiresIsolation"]!.GetValue<bool>());
        Assert.False(installed["usesEphemeralProfileStorage"]!.GetValue<bool>());
        // A profile name alone never isolates; it only keeps an isolated launch's storage.
        Assert.False(Plan(Environment("namedProfile"))["requiresIsolation"]!.GetValue<bool>());
    }

    [Fact]
    public void OnlyANamedIsolatedProfileKeepsPersistentWebStorage() {
        Assert.True(Plan(Environment("isolatedSession"))["usesEphemeralProfileStorage"]!.GetValue<bool>());
        Assert.False(Plan(Environment("isolatedSession", "namedProfile"))["usesEphemeralProfileStorage"]!.GetValue<bool>());
    }

    [Fact]
    public void OnlyTheTestRuntimeSuppressesInstalledApplicationUI() {
        Assert.False(Plan(Environment("testRuntime"))["presentsInstalledApplicationUI"]!.GetValue<bool>());
        Assert.True(Plan(Environment("isolatedSession"))["presentsInstalledApplicationUI"]!.GetValue<bool>());
        Assert.True(Plan(Environment("previewRuntime"))["presentsInstalledApplicationUI"]!.GetValue<bool>());
    }

    [Theory]
    [InlineData("desktop", null, false, "showStartPage")]
    [InlineData("desktop", "lastActiveTab", false, "lastActiveTab")]
    [InlineData("desktop", "showStartPage", true, "lastActiveTab")]
    [InlineData("mobile", "retiredChoice", false, "showStartPage")]
    [InlineData("mobile", "", false, "showStartPage")]
    public void TheSavedStartupChoiceAppliesUnlessSetupOwnsTheFirstWindow(string platform, string? stored, bool gate,
        string expected) =>
        Assert.Equal(expected, Plan(Environment(), platform, stored, gate)["startupBehavior"]!.GetValue<string>());

    [Fact]
    public void IsolatedLaunchesRestoreTheirStagedTabExceptTheMobileShowcase() {
        Assert.Equal("lastActiveTab", Plan(Environment("resetSession"), "mobile", "showStartPage")["startupBehavior"]!.GetValue<string>());
        Assert.Equal("lastActiveTab", Plan(Environment("showcase"), "desktop")["startupBehavior"]!.GetValue<string>());
        Assert.Equal("showStartPage", Plan(Environment("showcase"), "mobile", "lastActiveTab")["startupBehavior"]!.GetValue<string>());
        Assert.Equal(StartupBehavior.ShowStartPage, LaunchPolicy.DefaultStartup);
    }

    [Fact]
    public void TheEnvironmentMustNameEveryFlag() {
        var partial = Environment();
        partial.Remove("updateTestFeed");
        Assert.Throws<KeyNotFoundException>(() => Plan(partial));
        var extra = Environment();
        extra["futureFlag"] = true;
        Assert.Equal(ProtocolErrorCodes.UnexpectedMember, Assert.Throws<ProtocolException>(() => Plan(extra)).Code);
    }
}
