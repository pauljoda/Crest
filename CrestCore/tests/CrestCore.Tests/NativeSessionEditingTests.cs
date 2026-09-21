using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static byte[] EditRequest(JsonNode space, string operation, JsonObject arguments) =>
        Encoding.UTF8.GetBytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = operation,
            ["space"] = space.DeepClone(),
            ["arguments"] = arguments,
            ["now"] = 800000001.0
        }.ToJsonString());

    [Theory]
    [InlineData("getting-started")]
    [InlineData("future-native-view")]
    public void NativeContentKindsSurviveDomainRestoreAndSessionWrite(string kind) {
        var fixture = SavedSession();
        var saved = fixture.Document["session"]!["spaces"]![0]!["tabs"]![0]!.AsObject();
        saved["url"] = null;
        saved["savedURL"] = null;
        saved["title"] = "Stored native title";
        saved["nativeContent"] = new JsonObject { ["kind"] = kind, ["resourceID"] = Guid.NewGuid().ToString() };

        var document = new LegacySessionDocument(fixture.Document);
        var state = document.Read(new SystemIdSource());
        var tab = BrowserTab.Restore(state.Spaces[0].Tabs[0]);
        Assert.Equal(TabRenderType.UiNative, tab.Content.RenderType);
        Assert.Equal(kind, tab.Content.NativeKind);
        Assert.Equal("Stored native title", tab.Title);
        Assert.Equal(TabPhase.Ready, tab.Phase);

        var written = document.Write(state);
        var output = written["session"]!["spaces"]![0]!["tabs"]![0]!;
        Assert.True(JsonNode.DeepEquals(saved["nativeContent"], output["nativeContent"]));
        Assert.Equal("Stored native title", output["title"]!.GetValue<string>());
    }

    [Fact]
    public void NativeOpenAndClosePreserveDurableTabsAndPublishTheRequestedSelection() {
        var f = SavedSession(); var original = f.Document["session"]!["spaces"]![0]!;
        var newId = Guid.NewGuid();
        var input = EditRequest(original, "tab.open", new() {
            ["select"] = true,
            ["tab"] = new JsonObject {
                ["id"] = SwiftId(newId),
                ["title"] = "New page",
                ["url"] = "https://example.org/",
                ["placement"] = "current",
                ["symbol"] = "globe",
                ["lastActivatedAt"] = 800000001.0
            }
        });
        var bytes = NativeSessionEditor.Evaluate(input);
        Assert.Equal(bytes, NativeSessionEditor.Evaluate(input)); // ABI size probing must not invent a second identity.
        var opened = JsonNode.Parse(bytes)!;
        Assert.Equal(newId.ToString(), opened["tabId"]!.GetValue<string>());
        var space = opened["space"]!;
        Assert.Equal(2, space["tabs"]!.AsArray().Count);
        Assert.True(JsonNode.DeepEquals(original["tabs"]![0]!["futureTabProperty"], space["tabs"]![0]!["futureTabProperty"]));
        Assert.True(JsonNode.DeepEquals(original["branding"], space["branding"]));
        var closed = JsonNode.Parse(NativeSessionEditor.Evaluate(EditRequest(space, "tab.close", new() { ["tabId"] = newId.ToString(), ["fallbackTabId"] = f.Tab.Value.ToString() })))!["space"]!;
        Assert.Single(closed["tabs"]!.AsArray());
        Assert.Single(closed["archivedTabs"]!.AsArray());
        Assert.True(JsonNode.DeepEquals(SwiftId(f.Tab.Value), closed["selectedTabID"]));
        Assert.Equal("closed", closed["archivedTabs"]![0]!["reason"]!.GetValue<string>());
    }

    [Fact]
    public void NativeCloseCannotRemoveASavedTabAndClearSkipsStartPageArchive() {
        var f = SavedSession(); var original = f.Document["session"]!["spaces"]![0]!;
        Assert.Throws<BrowserRuleException>(() => NativeSessionEditor.Evaluate(EditRequest(original, "tab.close",
            new() { ["tabId"] = f.Tab.Value.ToString() })));
        var tab = original["tabs"]![0]!.AsObject();
        tab["placement"] = "current"; tab["url"] = null; tab["folderID"] = null;
        var cleared = JsonNode.Parse(NativeSessionEditor.Evaluate(EditRequest(original, "tab.clear_current", new())))!["space"]!;
        Assert.Empty(cleared["tabs"]!.AsArray());
        Assert.Empty(cleared["archivedTabs"]!.AsArray());
        Assert.Null(cleared["selectedTabID"]);
    }
}
