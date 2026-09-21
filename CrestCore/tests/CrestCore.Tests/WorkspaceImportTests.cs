using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static byte[] ImportCommand(JsonNode session, JsonArray sources) => Bytes(new JsonObject {
        ["version"] = 1,
        ["operation"] = "workspace.import",
        ["mode"] = "portable",
        ["now"] = 800000000.0,
        ["arguments"] = new JsonObject { ["sources"] = sources },
        ["window"] = JsonNode.Parse(Selection(session))
    });

    [Fact]
    public void ImportReidentifiesCollisionsWithoutPublishingUntilDurableCommit() {
        var session = SavedSession().Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session));
        var command = owner.PrepareCommand(1, ImportCommand(session, new JsonArray(session["spaces"]![0]!.DeepClone())));
        var result = JsonNode.Parse(command.Output)!;
        var imported = result["session"]!["spaces"]![1]!;
        Assert.NotEqual(session["spaces"]![0]!["id"]!.ToJsonString(), imported["id"]!.ToJsonString());
        Assert.True(JsonNode.DeepEquals(imported["id"], result["session"]!["selectedSpaceID"]));
        Assert.NotEqual(session["spaces"]![0]!["profile"]!["id"]!.ToJsonString(), imported["profile"]!["id"]!.ToJsonString());
        Assert.Equal(1, result["assets"]!.AsArray().Single(a => a!["spaceIndex"]!.GetValue<int>() == 1)!["sourceIndex"]!.GetValue<int>());
        using (command.Reserve(Selection(result["session"]!))) { }
        Assert.Equal(1UL, owner.Revision);
        using var accepted = command.Reserve(Selection(result["session"]!));
        Assert.Equal(2, JsonNode.Parse(accepted.Checkpoint.Read("core"))!["spaces"]!.AsArray().Count);
        accepted.Commit();
        Assert.Throws<BrowserRuleException>(() => command.Commit());
    }

    [Fact]
    public void RejectedImportCannotBeCommittedOrReservedAndKeepsTheSourceIntact() {
        var session = SavedSession().Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session));
        var sources = new JsonArray(Enumerable.Range(0, 64).Select(_ => session["spaces"]![0]!.DeepClone()).ToArray());
        var command = owner.PrepareCommand(1, ImportCommand(session, sources));
        Assert.Equal("space_limit_reached", JsonNode.Parse(command.Output)!["error"]!.GetValue<string>());
        Assert.Throws<BrowserRuleException>(() => command.Commit());
        Assert.Throws<BrowserRuleException>(() => command.Reserve(Selection(session)));
        Assert.Equal(1UL, owner.Revision);
    }
}
