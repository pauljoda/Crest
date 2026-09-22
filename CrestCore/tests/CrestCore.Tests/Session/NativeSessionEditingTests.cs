using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
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
        var closed = JsonNode.Parse(NativeSessionEditor.Evaluate(EditRequest(space, "tab.close", new() { ["tabId"] = newId.ToString(), ["fallbackTabId"] = f.Tab.ToString() })))!["space"]!;
        Assert.Single(closed["tabs"]!.AsArray());
        Assert.Single(closed["archivedTabs"]!.AsArray());
        Assert.True(JsonNode.DeepEquals(SwiftId(f.Tab), closed["selectedTabID"]));
        Assert.Equal("closed", closed["archivedTabs"]![0]!["reason"]!.GetValue<string>());
    }

    [Fact]
    public void ATabOpenedAfterASplitMemberLandsAfterTheWholeSplit() {
        var f = SavedSession(); var space = f.Document["session"]!["spaces"]![0]!.AsObject();
        var group = SwiftId(Guid.NewGuid()); var partner = Guid.NewGuid(); var plain = Guid.NewGuid();
        var first = space["tabs"]![0]!.AsObject();
        first["placement"] = "current"; first["folderID"] = null; first["savedURL"] = null; first["splitGroupID"] = group.DeepClone();
        JsonObject Current(Guid id, JsonObject? split) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = "https://example.org/" + id,
            ["placement"] = "current",
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0,
            ["splitGroupID"] = split
        };
        space["tabs"]!.AsArray().Add(Current(partner, (JsonObject)group.DeepClone()));
        space["tabs"]!.AsArray().Add(Current(plain, null));
        Guid[] Order(JsonObject arguments) => JsonNode.Parse(NativeSessionEditor.Evaluate(EditRequest(space, "tab.open", arguments)))!
            ["space"]!["tabs"]!.AsArray().Select(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>())).ToArray();
        JsonObject Open(Guid id, Guid? after) => new() {
            ["tab"] = Current(id, null),
            ["after"] = after?.ToString(),
            ["select"] = true
        };

        var opened = Guid.NewGuid();
        Assert.Equal([f.Tab, partner, opened, plain], Order(Open(opened, f.Tab)));
        Assert.Equal([f.Tab, partner, plain, opened], Order(Open(opened, plain)));
        // An origin outside the Space leaves the tab to its section's default place.
        Assert.Equal([opened, f.Tab, partner, plain], Order(Open(opened, Guid.NewGuid())));
        var both = Open(opened, f.Tab); both["index"] = 0;
        Assert.Throws<ProtocolException>(() => NativeSessionEditor.Evaluate(EditRequest(space, "tab.open", both)));
    }

    [Fact]
    public void SessionEditIgnoresFieldsUnrelatedToTheSelectedOperation() {
        var fixture = SavedSession();
        var space = fixture.Document["session"]!["spaces"]![0]!;
        var output = JsonNode.Parse(NativeSessionEditor.Evaluate(EditRequest(space, "tab.rename", new() {
            ["tabId"] = fixture.Tab.ToString("D"),
            ["title"] = "Readable name",
            ["ids"] = "unrelated invalid list",
            ["placement"] = new JsonObject { ["unexpected"] = true }
        })))!;

        Assert.Equal("Readable name", output["space"]!["tabs"]![0]!["customTitle"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(space["tabs"]![0]!["futureTabProperty"],
            output["space"]!["tabs"]![0]!["futureTabProperty"]));
    }

    [Fact]
    public void NativeCloseCannotRemoveASavedTabAndClearSkipsStartPageArchive() {
        var f = SavedSession(); var original = f.Document["session"]!["spaces"]![0]!;
        Assert.Throws<BrowserRuleException>(() => NativeSessionEditor.Evaluate(EditRequest(original, "tab.close",
            new() { ["tabId"] = f.Tab.ToString() })));
        var tab = original["tabs"]![0]!.AsObject();
        tab["placement"] = "current"; tab["url"] = null; tab["folderID"] = null;
        var cleared = JsonNode.Parse(NativeSessionEditor.Evaluate(EditRequest(original, "tab.clear_current", new())))!["space"]!;
        Assert.Empty(cleared["tabs"]!.AsArray());
        Assert.Empty(cleared["archivedTabs"]!.AsArray());
        Assert.Null(cleared["selectedTabID"]);
    }
}
