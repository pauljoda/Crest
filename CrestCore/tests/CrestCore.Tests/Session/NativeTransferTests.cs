using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static NativeSessionAuthority Borrow(NativeSessionAuthority owner, JsonNode session) => owner.CreateBorrowed(
        Guid.Parse(session["spaces"]![0]!["id"]!["rawValue"]!.GetValue<string>()),
        Guid.Parse(session["spaces"]![0]!["profile"]!["id"]!.GetValue<string>()));
    private static JsonNode EmptyTemporary(JsonNode source, bool isPrivate = false) {
        var value = source.DeepClone(); value["coreWorkspaceKind"] = "temporary"; value["corePrivateBrowsing"] = isPrivate;
        foreach (var space in value["spaces"]!.AsArray()) {
            foreach (var key in new[] { "tabs", "folders", "history", "archivedTabs", "splitGroups" }) space![key] = new JsonArray();
            space!["selectedTabID"] = null;
        }
        return value;
    }
    /// A move of the source's first tab to another workspace, issued from
    /// `windows` when given: the window it left and the one it moves to.
    private static byte[] TransferRequest(JsonNode source, (Guid Source, Guid Destination)? windows = null) => Bytes(new JsonObject {
        ["version"] = 1,
        ["spaceId"] = source["spaces"]![0]!["id"]!.DeepClone(),
        ["profileId"] = source["spaces"]![0]!["profile"]!["id"]!.DeepClone(),
        ["sourceWindowId"] = windows?.Source.ToString(),
        ["destinationWindowId"] = windows?.Destination.ToString(),
        ["now"] = 800000010.0,
        ["arguments"] = new JsonObject { ["tabId"] = source["spaces"]![0]!["tabs"]![0]!["id"]!.DeepClone(), ["select"] = true }
    });
    [Fact]
    public void TransferReservesBothGraphsCancelsWithoutMutationAndPreservesOpaqueMetadata() {
        var source = SavedSession().Document["session"]!; var target = EmptyTemporary(source);
        var a = new NativeSessionAuthority(Bytes(source)); var b = Borrow(a, source);
        using var device = new TestDevice(a);
        var windows = (Source: device.Showing(source), Destination: device.ShowingIn(device.Attach(b), target));
        var original = a.Checkpoint().Read("core");
        using (var cancelled = NativeSessionAuthority.PrepareTransfer(a, b, TransferRequest(source))) {
            cancelled.Reserve();
            Assert.Throws<BrowserRuleException>(() => a.Commit(RenameDelta(source, "Racing source")));
            Assert.Throws<BrowserRuleException>(() => b.Commit(Bytes(new JsonObject { ["version"] = 1, ["spaces"] = new JsonArray() })));
            Assert.Equal(original, a.Checkpoint().Read("core"));
        }
        Assert.Equal(1UL, a.Revision); Assert.Equal(1UL, b.Revision);
        using var accepted = NativeSessionAuthority.PrepareTransfer(a, b, TransferRequest(source, windows));
        accepted.Reserve();
        var removed = JsonNode.Parse(accepted.SourceCheckpoint.Read("core"))!["spaces"]![0]!;
        var inserted = JsonNode.Parse(accepted.DestinationCheckpoint.Read("core"))!["spaces"]![0]!;
        Assert.Empty(removed["tabs"]!.AsArray()); Assert.Empty(removed["archivedTabs"]!.AsArray()); Assert.Null(removed["selectedTabID"]);
        var moved = inserted["tabs"]![0]!;
        Assert.True(JsonNode.DeepEquals(source["spaces"]![0]!["tabs"]![0]!["iconAccent"], moved["iconAccent"]));
        Assert.Null(inserted["selectedTabID"]);
        Assert.Equal("current", moved["placement"]!.GetValue<string>()); Assert.Null(moved["folderID"]); Assert.Null(moved["savedURL"]);
        accepted.Commit();
        Assert.Equal(2UL, a.Revision); Assert.Equal(2UL, b.Revision);
        // Each window follows the move: the source shows nothing once its tab
        // left, and the destination shows the tab it received.
        var spaceId = SpaceId(inserted); var movedId = Guid.Parse(moved["id"]!["rawValue"]!.GetValue<string>());
        Assert.Null(device.Tab(windows.Source, spaceId));
        Assert.Equal(movedId, device.Tab(windows.Destination, spaceId));
        Assert.Throws<BrowserRuleException>(() => accepted.Commit());
    }
    [Fact]
    public void TransferRejectsStaleDestinationDuplicateIdentityAndPrivateBoundary() {
        var source = SavedSession().Document["session"]!; var target = EmptyTemporary(source);
        var a = new NativeSessionAuthority(Bytes(source)); var b = Borrow(a, source);
        using var prepared = NativeSessionAuthority.PrepareTransfer(a, b, TransferRequest(source));
        b.Commit(Bytes(new JsonObject { ["version"] = 1, ["spaces"] = new JsonArray() }));
        Assert.IsType<StaleCommand>(Assert.Throws<Rejected>(() => prepared.Reserve()).Rejection);
        Assert.Equal(1UL, a.Revision);
        // A failed destination reservation must release the source writer.
        a.Commit(RenameDelta(source, "Still writable"));
        var privateSession = source.DeepClone(); privateSession["coreWorkspaceKind"] = "private";
        var privateOwner = new NativeSessionAuthority(Bytes(privateSession));
        var privateTarget = Borrow(privateOwner, source);
        Assert.Equal("private_workspace_boundary", Assert.Throws<BrowserRuleException>(() =>
            NativeSessionAuthority.PrepareTransfer(a, privateTarget, TransferRequest(source))).Code);
        var unrelatedOwner = new NativeSessionAuthority(Bytes(source));
        var unrelatedTarget = Borrow(unrelatedOwner, source);
        Assert.Equal("different_profile_owner", Assert.Throws<BrowserRuleException>(() =>
            NativeSessionAuthority.PrepareTransfer(a, unrelatedTarget, TransferRequest(source))).Code);
        var duplicate = source.DeepClone();
        var duplicateOwner = Borrow(a, source);
        var space = duplicate["spaces"]![0]!;
        duplicateOwner.Commit(Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject { ["id"] = space["id"]!.DeepClone(), ["tabs"] = new JsonObject { ["replace"] = space["tabs"]!.DeepClone() } })
        }));
        Assert.Equal("duplicate_tab", Assert.Throws<BrowserRuleException>(() =>
            NativeSessionAuthority.PrepareTransfer(a, duplicateOwner, TransferRequest(source))).Code);
        b.PrepareBorrowedRefresh().Commit();
        var badRequest = JsonNode.Parse(TransferRequest(source))!; badRequest["profileId"] = Guid.NewGuid().ToString();
        Assert.Equal("wrong_profile_identity", Assert.Throws<BrowserRuleException>(() =>
            NativeSessionAuthority.PrepareTransfer(a, b, Bytes(badRequest))).Code);
    }
    [Fact]
    public void CrossSpaceMoveUsesOwnedRecordsAndRejectsFullPinnedDestinationWithoutPublishing() {
        var source = SavedSession().Document["session"]!;
        var target = SavedSession().Document["session"]!["spaces"]![0]!.DeepClone();
        source["spaces"]!.AsArray().Add(target);
        var original = source["spaces"]![0]!; var tab = original["tabs"]![0]!;
        Guid? window = null;
        byte[] Request(string placement) => Bytes(new JsonObject {
            ["version"] = 1,
            ["operation"] = "tab.transfer",
            ["spaceId"] = original["id"]!.DeepClone(),
            ["profileId"] = original["profile"]!["id"]!.DeepClone(),
            ["destinationSpaceId"] = target["id"]!.DeepClone(),
            ["destinationProfileId"] = target["profile"]!["id"]!.DeepClone(),
            ["windowId"] = window?.ToString(),
            ["now"] = 800000011.0,
            ["arguments"] = new JsonObject { ["tabId"] = tab["id"]!.DeepClone(), ["placement"] = placement }
        });
        var owner = new NativeSessionAuthority(Bytes(source));
        using var device = new TestDevice(owner);
        window = device.Showing(source);
        var command = owner.PrepareCommand(Request("saved"));
        Assert.Equal(1UL, owner.Revision);
        var projection = JsonNode.Parse(command.Output)!;
        Assert.Empty(projection["source"]!["tabs"]!.AsArray());
        Assert.Equal(2, projection["destination"]!["tabs"]!.AsArray().Count);
        command.Commit();
        // The window's shown tab moved away, so it shows nothing in the source;
        // the destination keeps what it shows.
        Assert.Null(device.Tab(window.Value, SpaceId(original)));
        Assert.Equal(SpaceId(target["tabs"]![0]!), device.Tab(window.Value, SpaceId(target)));
        var pinned = new JsonArray(Enumerable.Range(0, 12).Select(_ => { var t = tab.DeepClone(); t["id"] = SwiftId(Guid.NewGuid()); t["placement"] = "pinned"; t["folderID"] = null; return t; }).ToArray());
        target["tabs"] = pinned;
        var full = new NativeSessionAuthority(Bytes(source));
        window = null;
        Assert.IsType<PinnedTabsFull>(Assert.Throws<Rejected>(() => full.PrepareCommand(Request("pinned"))).Rejection);
        Assert.Equal(1UL, full.Revision);
    }
}
