using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static JsonObject BatchArguments(JsonNode space, string kind) => new() {
        ["kind"] = kind,
        ["selection"] = new JsonObject {
            ["roots"] = new JsonArray(space["tabs"]!.AsArray().Select(t => (JsonNode)new JsonObject { ["id"] = t!["id"]!.DeepClone(), ["folder"] = false }).ToArray()),
            ["tabs"] = new JsonArray(space["tabs"]!.AsArray().Select(t => (JsonNode)new JsonObject {
                ["id"] = t!["id"]!.DeepClone(),
                ["placement"] = t["placement"]!.DeepClone(),
                ["folderId"] = t["folderID"]?.DeepClone(),
                ["splitGroupId"] = t["splitGroupID"]?.DeepClone()
            }).ToArray()),
            ["folders"] = new JsonArray()
        }
    };

    [Fact]
    public void OwnedBatchCopiesCurrentMetadataAndRejectsStaleOrCancelledPublication() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        var core = new NativeSessionAuthority(Bytes(session));
        var args = BatchArguments(space, "Duplicate");
        var stale = core.PrepareCommand(1, SpaceCommand(session, "tabs.batch", args.DeepClone().AsObject()));
        core.PrepareCommand(1, SpaceCommand(session, "tab.rename", new() { ["tabId"] = fixture.Tab.ToString(), ["title"] = "Latest shared name" })).Commit();
        Assert.Throws<BrowserRuleException>(() => stale.Commit());
        var command = core.PrepareCommand(2, SpaceCommand(session, "tabs.batch", args.DeepClone().AsObject()));
        var output = JsonNode.Parse(command.Output)!;
        Assert.Null(output["error"]);
        var change = output["changes"]![0]!;
        Assert.Empty(change["space"]!["history"]!.AsArray());
        var copiedId = Guid.Parse(change["copies"]![0]!["copy"]!.GetValue<string>());
        var copy = change["space"]!["tabs"]!.AsArray().Single(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>()) == copiedId)!;
        Assert.Equal("Latest shared name", copy["customTitle"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(space["tabs"]![0]!["futureTabProperty"], copy["futureTabProperty"]));
        var before = core.Checkpoint(2, Selection(session)).Read("core");
        using (command.Reserve(Selection(session))) { }
        Assert.Equal(before, core.Checkpoint(2, Selection(session)).Read("core"));
        core.PrepareCommand(2, SpaceCommand(session, "tabs.batch", args.DeepClone().AsObject())).Commit();
        Assert.Equal(2, JsonNode.Parse(core.Checkpoint(3, Selection(session)).Read("core"))!["spaces"]![0]!["tabs"]!.AsArray().Count);
    }

    [Fact]
    public void BatchChecksCapturedPlacementAndRefusesTheEntireCrossSpaceMoveAtCapacity() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!; var source = session["spaces"]![0]!;
        source["tabs"]![0]!["placement"] = "pinned"; source["tabs"]![0]!["folderID"] = null; source["tabs"]![0]!["splitGroupID"] = null;
        var second = source["tabs"]![0]!.DeepClone(); second["id"] = SwiftId(Guid.NewGuid()); source["tabs"]!.AsArray().Add(second);
        var destination = source.DeepClone(); destination["id"] = SwiftId(Guid.NewGuid());
        destination["profile"]!["id"] = Guid.NewGuid().ToString(); destination["folders"] = new JsonArray();
        destination["tabs"] = new JsonArray(Enumerable.Range(0, 11).Select(_ => { var tab = second.DeepClone(); tab["id"] = SwiftId(Guid.NewGuid()); return tab; }).ToArray());
        destination["selectedTabID"] = destination["tabs"]![0]!["id"]!.DeepClone();
        session["spaces"]!.AsArray().Add(destination);
        var core = new NativeSessionAuthority(Bytes(session));
        var args = BatchArguments(source, "MoveToSpace");
        args["destinationSpaceId"] = destination["id"]!.DeepClone(); args["destinationProfileId"] = destination["profile"]!["id"]!.DeepClone();
        var before = core.Checkpoint(1, Selection(session)).Read("core");
        var rejected = core.PrepareCommand(1, SpaceCommand(session, "tabs.batch", args.DeepClone().AsObject()));
        Assert.Equal("pinned_capacity", JsonNode.Parse(rejected.Output)!["error"]!.GetValue<string>());
        Assert.Throws<BrowserRuleException>(() => rejected.Commit());
        Assert.Equal(before, core.Checkpoint(1, Selection(session)).Read("core"));
        core.PrepareCommand(1, SpaceCommand(session, "tab.move", new() { ["tabId"] = fixture.Tab.ToString(), ["placement"] = "current", ["detach"] = false })).Commit();
        var staleSelection = core.PrepareCommand(2, SpaceCommand(session, "tabs.batch", args.DeepClone().AsObject()));
        Assert.Equal("stale_selection", JsonNode.Parse(staleSelection.Output)!["error"]!.GetValue<string>());
        Assert.Throws<BrowserRuleException>(() => staleSelection.Commit());
    }
}
