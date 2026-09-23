using System.Text.Json.Nodes;

using CrestCore.Application;

using Xunit;

namespace CrestCore.Tests;

/// Selection is window state. Stored documents from earlier releases still carry
/// a session-level `selectedSpaceID` and per-Space `selectedTabID`; they must
/// load and never be written. Native storage folds them into windows once.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ALegacySelectionLoadsButNeverReachesACheckpointOrSurvivesAnEdit() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        Assert.NotNull(session["selectedSpaceID"]); Assert.NotNull(session["spaces"]![0]!["selectedTabID"]);
        var authority = new NativeSessionAuthority(Bytes(session));

        var saved = JsonNode.Parse(authority.Checkpoint(1).Read("core"))!;
        Assert.Null(saved["selectedSpaceID"]);
        Assert.Null(saved["spaces"]![0]!["selectedTabID"]);
        Assert.Equal("survives", saved["futureSessionProperty"]!.GetValue<string>());

        // A value delta from an older writer cannot put selection back.
        var metadata = session.DeepClone().AsObject(); metadata.Remove("spaces");
        var space = session["spaces"]![0]!.DeepClone().AsObject();
        foreach (var section in new[] { "tabs", "folders", "history", "archivedTabs" }) space.Remove(section);
        using (var replacement = authority.ReserveReplacement(1, Bytes(new JsonObject {
            ["version"] = 1,
            ["metadata"] = metadata,
            ["spaces"] = new JsonArray(new JsonObject { ["id"] = space["id"]!.DeepClone(), ["metadata"] = space })
        }))) {
            var written = JsonNode.Parse(replacement.Checkpoint.Read("core"))!;
            Assert.Null(written["selectedSpaceID"]);
            Assert.Null(written["spaces"]![0]!["selectedTabID"]);
        }

        // Showing a tab only records when it was last used; the answer suggests
        // nothing and the document still carries no selection.
        var touch = authority.PrepareCommand(1, SpaceCommand(session, "tab.touch", new() { ["tabId"] = fixture.Tab.ToString() }));
        Assert.True(LeavesSelection(JsonNode.Parse(touch.Output)!));
        touch.Commit();
        var touched = JsonNode.Parse(authority.Checkpoint(2).Read("core"))!["spaces"]![0]!;
        Assert.Equal(800000002.0, touched["tabs"]![0]!["lastActivatedAt"]!.GetValue<double>());
        Assert.Null(touched["selectedTabID"]);
    }

    [Fact]
    public void ClosingTheViewedTabHintsItsFallbackWhileOtherWindowsKeepTheirOwn() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        var current = space["tabs"]![0]!.DeepClone(); var currentId = Guid.NewGuid();
        current["id"] = SwiftId(currentId); current["placement"] = "current"; current["folderID"] = null;
        current["savedURL"] = null; current["splitGroupID"] = null;
        space["tabs"]!.AsArray().Add(current);
        var authority = new NativeSessionAuthority(Bytes(session));
        byte[] Close(Guid? viewed) {
            var request = JsonNode.Parse(SpaceCommand(session, "tab.close",
                new() { ["tabId"] = currentId.ToString(), ["fallbackTabId"] = fixture.Tab.ToString() }))!;
            request["view"] = new JsonObject {
                ["spaceId"] = fixture.Space.ToString(),
                ["tabs"] = new JsonArray(new JsonObject { ["spaceId"] = fixture.Space.ToString(), ["tabId"] = viewed?.ToString() })
            };
            return Bytes(request);
        }

        var viewing = JsonNode.Parse(authority.PrepareCommand(1, Close(currentId)).Output)!;
        Assert.True(HintsTab(viewing, fixture.Space, fixture.Tab));
        Assert.Null(HintedSpace(viewing));

        // A window showing another tab is not asked to change anything.
        Assert.True(LeavesSelection(JsonNode.Parse(authority.PrepareCommand(1, Close(fixture.Tab)).Output)!));
    }

    [Fact]
    public void LaunchCleanupKeepsEveryTabARestoredWindowShows() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        space["browsingPreferences"]!["currentTabCleanupPolicy"] = "after12Hours";
        Guid Stale() {
            var tab = space["tabs"]![0]!.DeepClone(); var id = Guid.NewGuid();
            tab["id"] = SwiftId(id); tab["placement"] = "current"; tab["folderID"] = null; tab["savedURL"] = null;
            tab["splitGroupID"] = null; tab["lastActivatedAt"] = 0.0;
            space["tabs"]!.AsArray().Add(tab);
            return id;
        }
        Guid shownElsewhere = Stale(), unshown = Stale();
        var authority = new NativeSessionAuthority(Bytes(session));
        var sweep = JsonNode.Parse(SpaceCommand(session, "records.sweep",
            new() { ["keepTabIds"] = new JsonArray(shownElsewhere.ToString()) }))!;
        sweep["view"] = null;
        authority.PrepareCommand(1, Bytes(sweep)).Commit();
        var tabs = JsonNode.Parse(authority.Checkpoint(2).Read("core"))!["spaces"]![0]!["tabs"]!.AsArray()
            .Select(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>())).ToArray();
        Assert.Contains(shownElsewhere, tabs);
        Assert.DoesNotContain(unshown, tabs);
    }
}
