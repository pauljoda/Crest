using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A tab's icon, the page it is showing and the page it belongs to are decided
/// once, here. The image bytes stay in the native cache; these edits only name
/// the tab whose stored image the platform must replace or drop.
public sealed partial class BrowserContractsTests {
    private static JsonNode Tab(JsonNode result) => result["space"]!["tabs"]![0]!;

    [Fact]
    public void ASavedTabCanAdoptThePageItIsShowingOrReturnToTheOneItBelongsTo() {
        var fixture = SavedSession();
        var space = fixture.Document["session"]!["spaces"]![0]!;
        var tabId = fixture.Tab.ToString();

        var restored = Edited(space, "tab.saved_location", new JsonObject { ["tabId"] = tabId, ["action"] = "restore" });
        Assert.True(restored["changed"]!.GetValue<bool>());
        Assert.Equal("https://example.com/", Tab(restored)["url"]!.GetValue<string>());
        // Already home, so there is nothing to adopt.
        Assert.False(Edited(restored["space"]!, "tab.saved_location",
            new JsonObject { ["tabId"] = tabId, ["action"] = "replace" })["changed"]!.GetValue<bool>());

        var adopted = Edited(space, "tab.saved_location", new JsonObject { ["tabId"] = tabId, ["action"] = "replace" });
        Assert.True(adopted["changed"]!.GetValue<bool>());
        Assert.Equal("https://example.com/article#one", Tab(adopted)["savedURL"]!.GetValue<string>());

        // A current tab is wherever browsing took it; it belongs nowhere.
        var current = space.DeepClone();
        current["tabs"]![0]!["placement"] = "current";
        current["tabs"]![0]!["savedURL"] = null;
        foreach (var action in new[] { "replace", "restore" })
            Assert.False(Edited(current, "tab.saved_location",
                new JsonObject { ["tabId"] = tabId, ["action"] = action })["changed"]!.GetValue<bool>());
    }

    [Fact]
    public void CreatingAFolderAroundTabsFilesThemInTheSameEdit() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        space["tabs"]![0]!["folderID"] = null;
        space["tabs"]![0]!["splitGroupID"] = null;
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var folder = Guid.NewGuid();

        var changes = device.Send(new CreateFolder(device.Workspace, fixture.Space, folder, TabPlacement.Saved, null, null, null, null,
            [fixture.Tab], LeavesSplits: false));

        var edited = core.Current.Spaces[0];
        Assert.Equal("New Folder", edited.Folders.Single(candidate => candidate.Id == folder).Title);
        Assert.Equal(folder, edited.Tabs.Single(tab => tab.Id == fixture.Tab).FolderId);
        // One edit, so no reader ever sees the folder empty.
        Assert.Single(changes.OfType<FoldersChanged>());
        Assert.Single(changes.OfType<TabsChanged>());
    }

}
