using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    /// One edit to a Space in a session of its own, answered the way the native
    /// caller reads it.
    private static JsonNode Edited(JsonNode space, string operation, JsonObject arguments) {
        var authority = new NativeSessionAuthority(Bytes(new JsonObject { ["spaces"] = new JsonArray(space.DeepClone()) }));
        return JsonNode.Parse(authority.PrepareCommand(1, Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = operation,
            ["spaceId"] = space["id"]!.DeepClone(),
            ["profileId"] = space["profile"]!["id"]!.DeepClone(),
            ["arguments"] = arguments,
            ["now"] = 800000001.0
        })).Output)!;
    }

    [Theory]
    [InlineData("getting-started")]
    [InlineData("future-native-view")]
    public void NativeContentKindsSurviveDomainRestoreAndSessionWrite(string kind) {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        var saved = session["spaces"]![0]!["tabs"]![0]!.AsObject();
        saved["url"] = null;
        saved["savedURL"] = null;
        saved["title"] = "Stored native title";
        saved["nativeContent"] = new JsonObject { ["kind"] = kind, ["resourceID"] = Guid.NewGuid().ToString().ToUpperInvariant() };

        var tab = BrowserTab.Restore(new TabState(fixture.Tab, "Stored native title", null, new NativeTabContent(kind), null, "square",
            null, null, null, TabPlacement.Saved, null, null, DateTimeOffset.UnixEpoch, null, null, null, false));
        Assert.Equal(TabRenderType.UiNative, tab.Content.RenderType);
        Assert.Equal(kind, tab.Content.NativeKind);
        Assert.Equal("Stored native title", tab.Title);

        // A rename runs the Space through the domain and back to its stored form.
        var renamed = Edited(session["spaces"]![0]!, "tab.rename", new() { ["tabId"] = fixture.Tab.ToString(), ["title"] = "Renamed" });
        var output = renamed["space"]!["tabs"]![0]!;
        Assert.True(JsonNode.DeepEquals(saved["nativeContent"], output["nativeContent"]));
        Assert.Equal("Stored native title", output["title"]!.GetValue<string>());
        Assert.Null(output["url"]);
    }

    [Fact]
    public void NavigatingANativeTabReplacesItsNativeContentWithAWebPage() {
        var fixture = SavedSession();
        var space = fixture.Document["session"]!["spaces"]![0]!;
        var tab = space["tabs"]![0]!.AsObject();
        tab["url"] = null;
        tab["savedURL"] = null;
        tab["nativeContent"] = new JsonObject { ["kind"] = "settings" };

        var result = Edited(space, "tab.observe", new() {
            ["tabId"] = fixture.Tab.ToString(),
            ["url"] = "https://example.org/",
            ["title"] = "Example"
        });
        var navigated = result["space"]!["tabs"]![0]!;
        Assert.Null(navigated["nativeContent"]);
        Assert.Equal("https://example.org/", navigated["url"]!.GetValue<string>());
        Assert.Equal("Example", navigated["title"]!.GetValue<string>());
    }

    [Fact]
    public void NativeOpenAndClosePreserveDurableTabsAndPublishTheRequestedSelection() {
        var f = SavedSession(); var original = f.Document["session"]!["spaces"]![0]!;
        var session = new JsonObject { ["spaces"] = new JsonArray(original.DeepClone()) };
        var authority = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(authority);
        var window = device.Open(f.Space, (f.Space, f.Tab));
        var elsewhere = device.Open(f.Space, (f.Space, f.Tab));
        var newId = Guid.NewGuid();
        var opening = authority.PrepareCommand(1, SpaceCommand(session, "tab.open", new() {
            ["select"] = true,
            ["tab"] = new JsonObject {
                ["id"] = SwiftId(newId),
                ["title"] = "New page",
                ["url"] = "https://example.org/",
                ["placement"] = "current",
                ["symbol"] = "globe",
                ["lastActivatedAt"] = 800000001.0
            }
        }, window: window));
        opening.Commit();
        var opened = JsonNode.Parse(opening.Output)!;
        Assert.Equal(newId.ToString(), opened["tabId"]!.GetValue<string>());
        // Only the window that opened the tab shows it.
        Assert.Equal(newId, device.Tab(window, f.Space));
        Assert.Equal(f.Tab, device.Tab(elsewhere, f.Space));
        var space = opened["space"]!;
        Assert.Equal(2, space["tabs"]!.AsArray().Count);
        Assert.True(JsonNode.DeepEquals(original["tabs"]![0], space["tabs"]![0]));
        Assert.True(JsonNode.DeepEquals(original["branding"], space["branding"]));
        // Closing the tab the window shows returns it to the tab it showed
        // before; the Space itself records no selection.
        var closing = authority.PrepareCommand(2, SpaceCommand(session, "tab.close", new() { ["tabId"] = newId.ToString() }, window: window));
        closing.Commit();
        var closed = JsonNode.Parse(closing.Output)!["space"]!;
        Assert.Single(closed["tabs"]!.AsArray());
        Assert.Single(closed["archivedTabs"]!.AsArray());
        Assert.Equal(f.Tab, device.Tab(window, f.Space));
        Assert.Null(closed["selectedTabID"]);
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
        Guid[] Order(JsonObject arguments) => Edited(space, "tab.open", arguments)
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
        Assert.Throws<ProtocolException>(() => Edited(space, "tab.open", both));
    }

    [Fact]
    public void SessionEditIgnoresFieldsUnrelatedToTheSelectedOperation() {
        var fixture = SavedSession();
        var space = fixture.Document["session"]!["spaces"]![0]!;
        var output = Edited(space, "tab.rename", new() {
            ["tabId"] = fixture.Tab.ToString("D"),
            ["title"] = "Readable name",
            ["ids"] = "unrelated invalid list",
            ["placement"] = new JsonObject { ["unexpected"] = true }
        });

        Assert.Equal("Readable name", output["space"]!["tabs"]![0]!["customTitle"]!.GetValue<string>());
    }

    [Fact]
    public void NativeCloseCannotRemoveASavedTabAndClearSkipsStartPageArchive() {
        var f = SavedSession(); var original = f.Document["session"]!["spaces"]![0]!;
        Assert.Throws<BrowserRuleException>(() => Edited(original, "tab.close", new() { ["tabId"] = f.Tab.ToString() }));
        var tab = original["tabs"]![0]!.AsObject();
        tab["placement"] = "current"; tab["url"] = null; tab["folderID"] = null;
        var cleared = Edited(original, "tab.clear_current", new())["space"]!;
        Assert.Empty(cleared["tabs"]!.AsArray());
        Assert.Empty(cleared["archivedTabs"]!.AsArray());
        Assert.Null(cleared["selectedTabID"]);
    }
}
