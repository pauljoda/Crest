using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class WindowStatePolicyTests {
    private static JsonNode Evaluate(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    private static JsonObject Space(Guid id, bool windowTab = false, bool captured = false, bool hasTabs = true) => new() {
        ["id"] = id.ToString("D"),
        ["windowTab"] = windowTab,
        ["captured"] = captured,
        ["hasTabs"] = hasTabs
    };

    private static JsonObject Repair(Guid selected, bool captures, JsonArray spaces, JsonArray? layouts = null) => new() {
        ["operation"] = "window.repair",
        ["selectedSpaceID"] = selected.ToString("D"),
        ["capturesSelection"] = captures,
        ["spaces"] = spaces,
        ["splitLayouts"] = layouts ?? []
    };

    [Fact]
    public void RepairKeepsLiveChoicesLeavesCapturedSpacesEmptyAndFallsBackOtherwise() {
        Guid kept = Guid.NewGuid(), empty = Guid.NewGuid(), first = Guid.NewGuid(), bare = Guid.NewGuid();
        var result = Evaluate(Repair(kept, true, [
            Space(kept, windowTab: true, captured: true),
            Space(empty, captured: true),
            Space(first),
            Space(bare, hasTabs: false)
        ]));
        Assert.Equal(["window", "none", "first", "none"],
            result["selections"]!.AsArray().Select(value => value!.GetValue<string>()));
        Assert.Equal(kept.ToString("D"), result["selectedSpaceID"]!.GetValue<string>());
        Assert.Equal(4, result["capturedSpaceIDs"]!.AsArray().Count);
    }

    [Fact]
    public void AMissingSpaceFallsBackToTheFirstSpaceAndLegacyWindowsStayUncaptured() {
        Guid gone = Guid.NewGuid(), other = Guid.NewGuid(), later = Guid.NewGuid();
        var toFirst = Evaluate(Repair(gone, false, [Space(other), Space(later)]));
        Assert.Equal(other.ToString("D"), toFirst["selectedSpaceID"]!.GetValue<string>());
        Assert.Null(toFirst["capturedSpaceIDs"]);
        var nothing = WindowStatePolicy.Repair(gone, false, [], []);
        Assert.Equal(gone, nothing.SelectedSpaceId);
    }

    [Fact]
    public void SplitLayoutsSurviveOnlyWhileTheirGroupRendersWithTheSameColumnCount() {
        Guid same = Guid.NewGuid(), grown = Guid.NewGuid(), gone = Guid.NewGuid();
        var repair = WindowStatePolicy.Repair(Guid.NewGuid(), true, [],
            [new(same, 3, 3), new(grown, 2, 3), new(gone, 2, null)]);
        Assert.Equal([same], repair.SplitLayouts);
    }

    [Fact]
    public void CapturedSharesAreValidatedAndNormalized() {
        Assert.Equal([0.25, 0.75], WindowStatePolicy.SplitFractions([0.25, 0.75]));
        Assert.Equal([0.5, 0.5], WindowStatePolicy.SplitFractions([0.3, 0.3]));
        Assert.Null(WindowStatePolicy.SplitFractions([]));
        Assert.Null(WindowStatePolicy.SplitFractions([0.2, 0.2, 0.2, 0.2, 0.2]));
        Assert.Null(WindowStatePolicy.SplitFractions([0.5, 0]));
        Assert.Null(WindowStatePolicy.SplitFractions([1.5, 0.5]));
        Assert.Null(WindowStatePolicy.SplitFractions([double.NaN, 0.5]));
        var wire = Evaluate(new() { ["operation"] = "window.split_layout", ["fractions"] = new JsonArray(0.2, 0.2) });
        Assert.Equal([0.5, 0.5], wire["fractions"]!.AsArray().Select(value => value!.GetValue<double>()));
        Assert.Null(Evaluate(new() { ["operation"] = "window.split_layout", ["fractions"] = new JsonArray() })["fractions"]);
    }

    [Fact]
    public void RepairIsBoundedAndRejectsDuplicateSpaces() {
        var many = new JsonArray(Enumerable.Range(0, WindowStatePolicy.MaximumSpaces + 1).Select(_ => (JsonNode?)Space(Guid.NewGuid())).ToArray());
        Assert.Equal(BrowserRuleCodes.WindowStateLimit,
            Assert.Throws<BrowserRuleException>(() => Evaluate(Repair(Guid.NewGuid(), true, many))).Code);
        var id = Guid.NewGuid();
        Assert.Equal(BrowserRuleCodes.DuplicateSpace,
            Assert.Throws<BrowserRuleException>(() => Evaluate(Repair(id, true, [Space(id), Space(id)]))).Code);
        var extra = Repair(id, true, [Space(id)]);
        extra["spaces"]![0]!["tabIDs"] = new JsonArray();
        Assert.Equal(ProtocolErrorCodes.UnexpectedMember, Assert.Throws<ProtocolException>(() => Evaluate(extra)).Code);
    }

    [Fact]
    public void TearOffCarriesOneUnlockedTabStillInItsSpace() {
        Assert.True(WindowStatePolicy.AllowsTearOff(true, false, true, null, false));
        Assert.True(WindowStatePolicy.AllowsTearOff(true, false, true, 1, true));
        Assert.False(WindowStatePolicy.AllowsTearOff(true, false, true, 2, true));
        Assert.False(WindowStatePolicy.AllowsTearOff(true, false, true, 1, false));
        Assert.False(WindowStatePolicy.AllowsTearOff(true, true, true, null, false));
        Assert.False(WindowStatePolicy.AllowsTearOff(false, false, true, null, false));
        Assert.False(WindowStatePolicy.AllowsTearOff(true, false, false, null, false));
        var wire = Evaluate(new() {
            ["operation"] = "window.tear_off",
            ["spaceMatches"] = true,
            ["spaceLocked"] = false,
            ["containsTab"] = true,
            ["selectionCount"] = 3,
            ["selectionIncludesTab"] = true
        });
        Assert.False(wire["allowed"]!.GetValue<bool>());
    }

    [Fact]
    public void SessionSelectionFallsBackToOpenThenPinnedThenTheFirstTab() {
        Assert.Equal(1, TabSelectionPolicy.Fallback([TabPlacement.Pinned, TabPlacement.Current]));
        Assert.Equal(1, TabSelectionPolicy.Fallback([TabPlacement.Saved, TabPlacement.Pinned]));
        Assert.Equal(0, TabSelectionPolicy.Fallback([TabPlacement.Saved]));
        Assert.Null(TabSelectionPolicy.Fallback([]));
        var wire = Evaluate(new() { ["operation"] = "tabs.selection_fallback", ["placements"] = new JsonArray("saved", "current") });
        Assert.Equal(1, wire["index"]!.GetValue<int>());
        Assert.Null(Evaluate(new() { ["operation"] = "tabs.selection_fallback", ["placements"] = new JsonArray() })["index"]);
    }
}
