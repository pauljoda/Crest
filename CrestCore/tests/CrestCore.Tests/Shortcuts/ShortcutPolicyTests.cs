using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class ShortcutPolicyTests {
    /// Every command identity the native layer persists, in its display order.
    private static readonly string[] Commands = [
        "newWindow", "newBlankWindow", "newTab", "newQuickWindow", "newPrivateWindow", "closeTabOrWindow", "closeWindow",
        "openLocation", "back", "forward", "reloadPage", "stopLoading", "reloadFromOrigin", "toggleSelectedTabPinned",
        "duplicateTab", "reopenClosedTab", "clearUnpinnedTabs", "archiveTab", "previousTab", "nextTab", "mostRecentTab",
        "selectTab1", "selectTab2", "selectTab3", "selectTab4", "selectTab5", "selectTab6", "selectTab7", "selectTab8",
        "selectTab9", "previousSpace", "nextSpace", "selectSpace1", "selectSpace2", "selectSpace3", "selectSpace4",
        "selectSpace5", "selectSpace6", "selectSpace7", "selectSpace8", "selectSpace9", "toggleReaderMode",
        "toggleContentBlocking", "findInPage", "zoomIn", "zoomOut", "actualSize", "copyPageLink", "copyPageLinkAsMarkdown",
        "sharePage", "exportPDF", "saveWebArchive", "printPage", "toggleSidebar", "showHistory", "showArchive",
        "showDownloads", "webInspectorInstructions", "splitWithNextTab", "focusNextSplitCard", "focusPreviousSplitCard",
        "removeTabFromSplit", "separateSplitTabs", "moveSplitCardLeft", "moveSplitCardRight", "toggleDeveloperToolbar",
        "toggleTranslationToolbar", "openFile"
    ];

    private static readonly Dictionary<string, ShortcutChord?> None = [];

    private static ShortcutChord Key(string character, int modifiers) => ShortcutChord.Character(character, modifiers);

    private static JsonNode Evaluate(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    private static JsonArray Names(IEnumerable<string> commands) => new(commands.Select(c => (JsonNode?)JsonValue.Create(c)).ToArray());

    private static JsonObject Chord(string character, int modifiers) =>
        new() { ["key"] = new JsonObject { ["character"] = character }, ["modifiers"] = modifiers };

    [Theory]
    [InlineData("desktop")]
    [InlineData("mobile")]
    public void TheDefaultCatalogNeverGivesTwoCommandsOneChord(string platform) {
        var defaults = Commands.Select(command => ShortcutCatalog.Default(command, DevicePlatform.Named(platform)!))
            .OfType<ShortcutChord>().ToArray();
        Assert.Equal(defaults.Length, defaults.Distinct().Count());
        Assert.All(defaults, chord => Assert.True(chord.IsValid));
    }

    [Fact]
    public void NumberedCommandsDefaultToCommandAndControlDigitsAndTheMacAddsABlankWindow() {
        Assert.Equal(Key("3", ShortcutChord.Command), ShortcutCatalog.Default("selectTab3", DevicePlatform.Mobile));
        Assert.Equal(Key("9", ShortcutChord.Control), ShortcutCatalog.Default("selectSpace9", DevicePlatform.Desktop));
        Assert.Null(ShortcutCatalog.Default("selectTab10", DevicePlatform.Desktop));
        Assert.Equal(Key("n", ShortcutChord.Command | ShortcutChord.Option),
            ShortcutCatalog.Default("newBlankWindow", DevicePlatform.Desktop));
        Assert.Null(ShortcutCatalog.Default("newBlankWindow", DevicePlatform.Mobile));
        Assert.Equal(Key("n", ShortcutChord.Command | ShortcutChord.Option),
            ShortcutCatalog.Default("newQuickWindow", DevicePlatform.Mobile));
        Assert.Null(ShortcutCatalog.Default("duplicateTab", DevicePlatform.Desktop));
    }

    [Fact]
    public void AConflictNamesOnlyOtherHoldersAndChangesNothingUntilConfirmed() {
        var chord = Key("g", ShortcutChord.Command | ShortcutChord.Shift);
        var first = ShortcutBindingPolicy.Assign("newTab", chord, false, Commands, None, DevicePlatform.Desktop);
        Assert.Equal(ShortcutAssignmentResult.Assigned, first.Result);
        var overrides = first.Overrides!;
        Assert.Equal(ShortcutAssignmentResult.Assigned,
            ShortcutBindingPolicy.Assign("newTab", chord, false, Commands, overrides, DevicePlatform.Desktop).Result);

        var blocked = ShortcutBindingPolicy.Assign("newWindow", chord, false, Commands, overrides, DevicePlatform.Desktop);
        Assert.Equal(ShortcutAssignmentResult.Conflict, blocked.Result);
        Assert.Equal(["newTab"], blocked.Conflicts);
        Assert.Null(blocked.Overrides);

        var replaced = ShortcutBindingPolicy.Assign("newWindow", chord, true, Commands, overrides, DevicePlatform.Desktop);
        Assert.Equal(ShortcutAssignmentResult.Assigned, replaced.Result);
        // The displaced command had a default, so it is recorded as unassigned.
        Assert.Null(ShortcutBindingPolicy.Effective("newTab", Commands, replaced.Overrides!, DevicePlatform.Desktop));
        Assert.True(replaced.Overrides!.ContainsKey("newTab"));
        Assert.Equal(chord, replaced.Overrides["newWindow"]);
    }

    [Fact]
    public void TakingADefaultChordConflictsWithItsDefaultHolderAndRestoringADefaultStoresNothing() {
        var find = Key("f", ShortcutChord.Command);
        var taken = ShortcutBindingPolicy.Assign("newTab", find, false, Commands, None, DevicePlatform.Desktop);
        Assert.Equal(["findInPage"], taken.Conflicts);
        var restored = ShortcutBindingPolicy.Assign("newTab", Key("t", ShortcutChord.Command), false, Commands,
            new Dictionary<string, ShortcutChord?> { ["newTab"] = Key("y", ShortcutChord.Option) }, DevicePlatform.Desktop);
        Assert.Empty(restored.Overrides!);
        var cleared = ShortcutBindingPolicy.Assign("duplicateTab", null, false, Commands, None, DevicePlatform.Desktop);
        Assert.Empty(cleared.Overrides!);
        var unassigned = ShortcutBindingPolicy.Assign("showHistory", null, false, Commands, None, DevicePlatform.Desktop);
        Assert.Null(unassigned.Overrides!["showHistory"]);
    }

    [Fact]
    public void AChordWithoutASupportedModifierIsNeverBound() {
        var plain = Key("t", 0);
        Assert.Equal(ShortcutAssignmentResult.Invalid,
            ShortcutBindingPolicy.Assign("newTab", plain, true, Commands, None, DevicePlatform.Desktop).Result);
        Assert.Equal(ShortcutAssignmentResult.Invalid,
            ShortcutBindingPolicy.Assign("newTab", Key("t", 1 << 5), true, Commands, None, DevicePlatform.Desktop).Result);
    }

    [Fact]
    public void OnlyOfferedCommandsCanHoldOrLoseAChord() {
        var reader = Key("r", ShortcutChord.Command | ShortcutChord.Option);
        var offered = Commands.Where(command => command != "toggleReaderMode").ToArray();
        var hidden = new Dictionary<string, ShortcutChord?> { ["toggleReaderMode"] = reader };
        Assert.Empty(ShortcutBindingPolicy.Assign("newTab", reader, false, offered, hidden, DevicePlatform.Desktop).Conflicts);
        Assert.Equal(["toggleReaderMode"],
            ShortcutBindingPolicy.Assign("newTab", reader, false, Commands, hidden, DevicePlatform.Desktop).Conflicts);
    }

    [Theory]
    [InlineData("newQuickWindow", "newBlankWindow", ShortcutChord.Command | ShortcutChord.Option)]
    [InlineData("newTab", "newQuickWindow", ShortcutChord.Command | ShortcutChord.Option | ShortcutChord.Shift)]
    public void TheMacWindowDefaultsYieldToAPersistedCustomChord(string owner, string displaced, int modifiers) {
        var overrides = new Dictionary<string, ShortcutChord?> { [owner] = Key("n", modifiers), ["showHistory"] = null };
        var bindings = ShortcutBindingPolicy.Resolve(Commands, overrides, DevicePlatform.Desktop).ToDictionary(b => b.Command);
        Assert.Equal(Key("n", modifiers), bindings[owner].Shortcut);
        Assert.Null(bindings[displaced].Shortcut);
        Assert.False(bindings[displaced].IsCustomized);
        Assert.Equal(Key("n", modifiers), bindings[displaced].Default);
        Assert.Null(bindings["showHistory"].Shortcut);
        Assert.True(bindings["showHistory"].IsCustomized);
    }

    [Fact]
    public void TheBindingsOperationKeepsPersistedValuesAndUnknownCommandsVerbatim() {
        var accented = Chord("é", ShortcutChord.Command | ShortcutChord.Option);
        var result = Evaluate(new() {
            ["operation"] = "shortcuts.bindings",
            ["platform"] = "desktop",
            ["commands"] = Names(Commands),
            ["overrides"] = new JsonObject { ["newTab"] = accented, ["retiredCommand"] = Chord("q", 1), ["showHistory"] = null }
        });
        var bindings = result["bindings"]!.AsArray().ToDictionary(b => b!["command"]!.GetValue<string>());
        Assert.Equal(Commands.Length, bindings.Count);
        Assert.Equal("é", bindings["newTab"]!["shortcut"]!["key"]!["character"]!.GetValue<string>());
        Assert.Null(bindings["showHistory"]!["shortcut"]);
        Assert.Equal("upArrow", bindings["previousTab"]!["shortcut"]!["key"]!["special"]!.GetValue<string>());

        var assigned = Evaluate(new() {
            ["operation"] = "shortcuts.assign",
            ["platform"] = "desktop",
            ["commands"] = Names(Commands),
            ["overrides"] = new JsonObject { ["newTab"] = accented.DeepClone(), ["retiredCommand"] = Chord("q", 1) },
            ["command"] = "newWindow",
            // The decomposed and composed spellings are the same chord.
            ["shortcut"] = Chord("é", ShortcutChord.Command | ShortcutChord.Option),
            ["replacingConflicts"] = false
        });
        Assert.Equal("conflict", assigned["result"]!.GetValue<string>());
        Assert.Equal("newTab", assigned["conflicts"]![0]!.GetValue<string>());
        Assert.Null(assigned["overrides"]);

        var replaced = Evaluate(new() {
            ["operation"] = "shortcuts.assign",
            ["platform"] = "desktop",
            ["commands"] = Names(Commands),
            ["overrides"] = new JsonObject { ["retiredCommand"] = Chord("q", 1) },
            ["command"] = "newTab",
            ["shortcut"] = Chord("g", 9),
            ["replacingConflicts"] = false
        });
        Assert.True(JsonNode.DeepEquals(Chord("q", 1), replaced["overrides"]!["retiredCommand"]));
        Assert.True(JsonNode.DeepEquals(Chord("g", 9), replaced["overrides"]!["newTab"]));
    }

    [Fact]
    public void AMalformedChordOrPlatformIsRejected() {
        var request = new JsonObject {
            ["operation"] = "shortcuts.bindings",
            ["platform"] = "tv",
            ["commands"] = Names(Commands),
            ["overrides"] = new JsonObject()
        };
        Assert.Equal(ProtocolErrorCodes.InvalidPlatform, Assert.Throws<ProtocolException>(() => Evaluate(request)).Code);
        request["platform"] = "mobile";
        request["overrides"] = new JsonObject {
            ["newTab"] = new JsonObject { ["key"] = new JsonObject { ["special"] = "hyper" }, ["modifiers"] = 1 }
        };
        Assert.Equal(BrowserRuleCodes.InvalidShortcut, Assert.Throws<BrowserRuleException>(() => Evaluate(request)).Code);
        request["overrides"] = new JsonObject();
        request["commands"] = Names(["newTab", "newTab"]);
        Assert.Equal(BrowserRuleCodes.DuplicateShortcutCommand, Assert.Throws<BrowserRuleException>(() => Evaluate(request)).Code);
    }

    [Fact]
    public void NumberedSelectionReachesTheNthTabOrSpaceOnlyWhenItExists() {
        var result = Evaluate(new() { ["operation"] = "shortcuts.numbered_selection", ["tabCount"] = 3, ["spaceCount"] = 0 });
        var selections = result["selections"]!.AsArray().ToDictionary(s => s!["command"]!.GetValue<string>());
        Assert.Equal(18, selections.Count);
        Assert.Equal(0, selections["selectTab1"]!["index"]!.GetValue<int>());
        Assert.Equal(2, selections["selectTab3"]!["index"]!.GetValue<int>());
        Assert.Equal("tab", selections["selectTab3"]!["target"]!.GetValue<string>());
        Assert.Null(selections["selectTab4"]!["index"]);
        Assert.Null(selections["selectSpace1"]!["index"]);
        Assert.Equal("space", selections["selectSpace1"]!["target"]!.GetValue<string>());
        Assert.Equal(8, NumberedSelectionPolicy.Resolve(20, 20).Single(s => s.Command == "selectSpace9").Index);
        Assert.Equal(BrowserRuleCodes.InvalidSpaceCount,
            Assert.Throws<BrowserRuleException>(() => NumberedSelectionPolicy.Resolve(0, -1)).Code);
    }
}
