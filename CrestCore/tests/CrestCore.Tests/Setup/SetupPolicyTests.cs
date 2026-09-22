using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class SetupPolicyTests {
    private static JsonNode Evaluate(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    private static JsonObject Tab(string placement, int existing, int added, string? title = null) => new() {
        ["operation"] = "setup.tab",
        ["placement"] = placement,
        ["existingPinnedCount"] = existing,
        ["addedPinnedCount"] = added,
        ["url"] = "https://www.example.com/start",
        ["title"] = title
    };

    [Fact]
    public void NewDraftSpacesAreNumberedCycleAccentsAndStopAtTheImportLimit() {
        var fifth = Evaluate(new() { ["operation"] = "setup.space", ["draftCount"] = 4 });
        Assert.Equal("Space 5", fifth["name"]!.GetValue<string>());
        Assert.Equal("indigo", fifth["accent"]!.GetValue<string>());
        Assert.Equal(ManualSetupPolicy.NewSpaceSymbol, fifth["symbol"]!.GetValue<string>());
        Assert.Equal("orange", Evaluate(new() { ["operation"] = "setup.space", ["draftCount"] = 1 })["accent"]!.GetValue<string>());
        var full = Evaluate(new() { ["operation"] = "setup.space", ["draftCount"] = WorkspaceImportPolicy.MaximumSpaces });
        Assert.Equal(BrowserRuleCodes.SpaceLimitReached, full["error"]!.GetValue<string>());
    }

    [Fact]
    public void TabsAreAdmittedWithinThePinnedLimitAndTakeTheirPlacementsPresentation() {
        var pinned = Evaluate(Tab("pinned", 10, 1));
        Assert.Equal("example.com", pinned["title"]!.GetValue<string>());
        Assert.Equal(ManualSetupPolicy.PinnedTabSymbol, pinned["symbol"]!.GetValue<string>());
        Assert.True(pinned["keepsSavedURL"]!.GetValue<bool>());
        Assert.Equal(BrowserRuleCodes.PinnedLimitReached, Evaluate(Tab("pinned", 11, 1))["error"]!.GetValue<string>());
        var open = Evaluate(Tab("current", 12, 12, "  Reading  "));
        Assert.Equal("Reading", open["title"]!.GetValue<string>());
        Assert.Equal(ManualSetupPolicy.TabSymbol, open["symbol"]!.GetValue<string>());
        Assert.False(open["keepsSavedURL"]!.GetValue<bool>());
        Assert.Equal("about:blank", ManualSetupPolicy.Title("about:blank", " "));
        Assert.Equal(ProtocolErrorCodes.InvalidPlacement, Assert.Throws<ProtocolException>(() => Evaluate(Tab("floating", 0, 0))).Code);
    }

    [Fact]
    public void ReconcileFollowsSpacesChangedElsewhereWithoutDiscardingNewDrafts() {
        Guid kept = Guid.NewGuid(), deleted = Guid.NewGuid(), draft = Guid.NewGuid(), created = Guid.NewGuid();
        var entries = ManualSetupPolicy.Reconcile(
            [new(kept, false), new(deleted, false), new(draft, true)], [created, kept]);
        Assert.Equal([new ManualSetupEntry(0, 1), new ManualSetupEntry(2, null), new ManualSetupEntry(null, 0)], entries);
        var wire = Evaluate(new() {
            ["operation"] = "setup.reconcile",
            ["drafts"] = new JsonArray(new JsonObject { ["id"] = kept.ToString("D"), ["isNew"] = false }),
            ["existing"] = new JsonArray(kept.ToString("D"))
        });
        Assert.Equal(0, wire["entries"]![0]!["draft"]!.GetValue<int>());
        Assert.Equal(0, wire["entries"]![0]!["existing"]!.GetValue<int>());
    }

    [Fact]
    public void CompletionOpensTheGuideOnRerunsAndTheFirstRunOnlyAndNeverFromPrivateBrowsing() {
        Assert.Equal(OnboardingCompletion.OpenGuide, OnboardingCompletionPolicy.Decide(OnboardingEntryPoint.FirstRun, false, false));
        Assert.Equal(OnboardingCompletion.Complete, OnboardingCompletionPolicy.Decide(OnboardingEntryPoint.FirstRun, true, false));
        Assert.Equal(OnboardingCompletion.OpenGuide, OnboardingCompletionPolicy.Decide(OnboardingEntryPoint.Rerun, true, false));
        Assert.Equal(OnboardingCompletion.Complete, OnboardingCompletionPolicy.Decide(OnboardingEntryPoint.ImportBrowser, false, false));
        Assert.Equal(OnboardingCompletion.SourceChanged, OnboardingCompletionPolicy.Decide(OnboardingEntryPoint.Rerun, false, true));
        var wire = Evaluate(new() {
            ["operation"] = "onboarding.completion",
            ["entryPoint"] = "manualSetup",
            ["hasCompletedSetup"] = false,
            ["isPrivateBrowsing"] = false
        });
        Assert.Equal("complete", wire["outcome"]!.GetValue<string>());
        Assert.Equal(ProtocolErrorCodes.InvalidEntryPoint, Assert.Throws<ProtocolException>(() => Evaluate(new() {
            ["operation"] = "onboarding.completion",
            ["entryPoint"] = "later",
            ["hasCompletedSetup"] = false,
            ["isPrivateBrowsing"] = false
        })).Code);
    }

    [Fact]
    public void TheGuideOpensOnlyWhenItsSpaceIsUnchangedFirstAndUnlocked() {
        var target = new OnboardingSpaceIdentity(Guid.NewGuid(), Guid.NewGuid());
        var other = new OnboardingSpaceIdentity(Guid.NewGuid(), Guid.NewGuid());
        var replacedProfile = target with { ProfileId = Guid.NewGuid() };
        Assert.True(OnboardingCompletionPolicy.ConfirmsGuide(new(target, other, other, null, null, target, true, false)));
        Assert.False(OnboardingCompletionPolicy.ConfirmsGuide(new(target, other, target, null, null, target, true, false)));
        Assert.False(OnboardingCompletionPolicy.ConfirmsGuide(new(target, other, other, null, null, null, true, false)));
        Assert.False(OnboardingCompletionPolicy.ConfirmsGuide(new(target, other, other, null, null, target, true, true)));
        Assert.True(OnboardingCompletionPolicy.ConfirmsGuide(new(target, null, target, null, null, null, false, false)));
        Assert.False(OnboardingCompletionPolicy.ConfirmsGuide(new(target, null, replacedProfile, null, null, null, false, false)));
        static JsonObject Identity(OnboardingSpaceIdentity value) => new() {
            ["spaceID"] = value.SpaceId.ToString("D"),
            ["profileID"] = value.ProfileId.ToString("D")
        };
        var wire = Evaluate(new() {
            ["operation"] = "onboarding.guide",
            ["target"] = Identity(target),
            ["originalFirst"] = null,
            ["currentFirst"] = Identity(target),
            ["originalTarget"] = null,
            ["currentTarget"] = null,
            ["previewFirst"] = null,
            ["hasManualPlan"] = false,
            ["locked"] = false
        });
        Assert.True(wire["confirmed"]!.GetValue<bool>());
    }
}
