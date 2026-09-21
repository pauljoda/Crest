using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static JsonNode EmptyTemporary(JsonNode source, bool isPrivate = false)
    {
        var value = source.DeepClone(); value["coreWorkspaceKind"] = "temporary"; value["corePrivateBrowsing"] = isPrivate;
        foreach (var space in value["spaces"]!.AsArray())
        {
            foreach (var key in new[] { "tabs", "folders", "history", "archivedTabs", "splitGroups" }) space![key] = new JsonArray();
            space!["selectedTabID"] = null;
        }
        return value;
    }
    private static byte[] TransferRequest(JsonNode source, JsonNode destination) => Bytes(new JsonObject
    {
        ["version"] = 1, ["spaceId"] = source["spaces"]![0]!["id"]!.DeepClone(),
        ["profileId"] = source["spaces"]![0]!["profile"]!["id"]!.DeepClone(),
        ["sourceWindow"] = JsonNode.Parse(Selection(source)), ["destinationWindow"] = JsonNode.Parse(Selection(destination)),
        ["now"] = 800000010.0, ["arguments"] = new JsonObject
        { ["tabId"] = source["spaces"]![0]!["tabs"]![0]!["id"]!.DeepClone(), ["select"] = true }
    });
    [Fact]
    public void TransferReservesBothGraphsCancelsWithoutMutationAndPreservesOpaqueMetadata()
    {
        var source = SavedSession().Document["session"]!; var target = EmptyTemporary(source);
        var a = new NativeSessionAuthority(Bytes(source)); var b = new NativeSessionAuthority(Bytes(target));
        var original = a.Checkpoint(1, Selection(source)).Read("core");
        using (var cancelled = NativeSessionAuthority.PrepareTransfer(a, 1, b, 1, TransferRequest(source, target)))
        {
            cancelled.Reserve();
            Assert.Throws<BrowserRuleException>(() => a.Commit(1, RenameDelta(source, "Racing source")));
            Assert.Throws<BrowserRuleException>(() => b.Commit(1, Bytes(new JsonObject { ["version"] = 1, ["spaces"] = new JsonArray() })));
            Assert.Equal(original, a.Checkpoint(1, Selection(source)).Read("core"));
        }
        Assert.Equal(1UL, a.Revision); Assert.Equal(1UL, b.Revision);
        using var accepted = NativeSessionAuthority.PrepareTransfer(a, 1, b, 1, TransferRequest(source, target));
        accepted.Reserve();
        var removed = JsonNode.Parse(accepted.SourceCheckpoint.Read("core"))!["spaces"]![0]!;
        var inserted = JsonNode.Parse(accepted.DestinationCheckpoint.Read("core"))!["spaces"]![0]!;
        Assert.Empty(removed["tabs"]!.AsArray()); Assert.Empty(removed["archivedTabs"]!.AsArray()); Assert.Null(removed["selectedTabID"]);
        var moved = inserted["tabs"]![0]!;
        Assert.True(JsonNode.DeepEquals(source["spaces"]![0]!["tabs"]![0]!["futureTabProperty"], moved["futureTabProperty"]));
        Assert.True(JsonNode.DeepEquals(moved["id"], inserted["selectedTabID"]));
        Assert.Equal("current", moved["placement"]!.GetValue<string>()); Assert.Null(moved["folderID"]); Assert.Null(moved["savedURL"]);
        Assert.Equal((2UL, 2UL), accepted.Commit());
        Assert.Throws<BrowserRuleException>(() => accepted.Commit());
    }
    [Fact]
    public void TransferRejectsStaleDestinationDuplicateIdentityAndPrivateBoundary()
    {
        var source = SavedSession().Document["session"]!; var target = EmptyTemporary(source);
        var a = new NativeSessionAuthority(Bytes(source)); var b = new NativeSessionAuthority(Bytes(target));
        using var prepared = NativeSessionAuthority.PrepareTransfer(a, 1, b, 1, TransferRequest(source, target));
        b.Commit(1, Bytes(new JsonObject { ["version"] = 1, ["spaces"] = new JsonArray() }));
        Assert.Throws<BrowserRuleException>(() => prepared.Reserve());
        Assert.Equal(1UL, a.Revision);
        // A failed destination reservation must release the source writer.
        a.Commit(1, RenameDelta(source, "Still writable"));
        var privateTarget = new NativeSessionAuthority(Bytes(EmptyTemporary(source, true)));
        Assert.Equal("private_workspace_boundary", Assert.Throws<BrowserRuleException>(() =>
            NativeSessionAuthority.PrepareTransfer(a, 2, privateTarget, 1, TransferRequest(source, target))).Code);
        var duplicate = source.DeepClone(); duplicate["coreWorkspaceKind"] = "temporary";
        var duplicateOwner = new NativeSessionAuthority(Bytes(duplicate));
        Assert.Equal("duplicate_tab", Assert.Throws<BrowserRuleException>(() =>
            NativeSessionAuthority.PrepareTransfer(a, 2, duplicateOwner, 1, TransferRequest(source, duplicate))).Code);
        var badRequest = JsonNode.Parse(TransferRequest(source, target))!; badRequest["profileId"] = Guid.NewGuid().ToString();
        Assert.Equal("wrong_profile_identity", Assert.Throws<BrowserRuleException>(() =>
            NativeSessionAuthority.PrepareTransfer(a, 2, b, 2, Bytes(badRequest))).Code);
    }
    [Fact]
    public void CrossSpaceMoveUsesOwnedRecordsAndRejectsFullPinnedDestinationWithoutPublishing()
    {
        var source = SavedSession().Document["session"]!;
        var target = SavedSession().Document["session"]!["spaces"]![0]!.DeepClone();
        source["spaces"]!.AsArray().Add(target);
        var original = source["spaces"]![0]!; var tab = original["tabs"]![0]!;
        byte[] Request(string placement) => Bytes(new JsonObject
        {
            ["version"] = 1, ["operation"] = "tab.transfer", ["spaceId"] = original["id"]!.DeepClone(),
            ["profileId"] = original["profile"]!["id"]!.DeepClone(), ["destinationSpaceId"] = target["id"]!.DeepClone(),
            ["destinationProfileId"] = target["profile"]!["id"]!.DeepClone(), ["window"] = JsonNode.Parse(Selection(source)),
            ["now"] = 800000011.0, ["arguments"] = new JsonObject { ["tabId"] = tab["id"]!.DeepClone(), ["placement"] = placement }
        });
        var owner = new NativeSessionAuthority(Bytes(source));
        var command = owner.PrepareCommand(1, Request("saved"));
        Assert.Equal(1UL, owner.Revision);
        var projection = JsonNode.Parse(command.Output)!;
        Assert.Empty(projection["source"]!["tabs"]!.AsArray()); Assert.Null(projection["source"]!["selectedTabID"]);
        Assert.Equal(2, projection["destination"]!["tabs"]!.AsArray().Count);
        Assert.True(JsonNode.DeepEquals(target["selectedTabID"], projection["destination"]!["selectedTabID"]));
        command.Commit();
        var pinned = new JsonArray(Enumerable.Range(0, 12).Select(_ =>
        { var t = tab.DeepClone(); t["id"] = SwiftId(Guid.NewGuid()); t["placement"] = "pinned"; t["folderID"] = null; return t; }).ToArray());
        target["tabs"] = pinned;
        var full = new NativeSessionAuthority(Bytes(source));
        Assert.Equal("pinned_limit", Assert.Throws<BrowserRuleException>(() => full.PrepareCommand(1, Request("pinned"))).Code);
        Assert.Equal(1UL, full.Revision);
    }
}
