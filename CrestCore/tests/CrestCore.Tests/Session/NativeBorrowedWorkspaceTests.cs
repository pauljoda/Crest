using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    /// A workspace that borrows the first Space of `session`, which `owner` holds.
    private static NativeSessionAuthority Borrow(NativeSessionAuthority owner, JsonNode session) => owner.CreateBorrowed(
        Guid.Parse(session["spaces"]![0]!["id"]!["rawValue"]!.GetValue<string>()),
        Guid.Parse(session["spaces"]![0]!["profile"]!["id"]!.GetValue<string>()));

    [Fact]
    public void BorrowingUsesOwnedPolicyAndCannotCreateOrRewriteAProfileFromASnapshot() {
        var session = SavedSession().Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session));
        var child = Borrow(owner, session);
        var projected = JsonNode.Parse(child.Checkpoint().Read("core"))!;
        var source = session["spaces"]![0]!; var space = projected["spaces"]![0]!;
        Assert.True(JsonNode.DeepEquals(source["profile"], space["profile"]));
        foreach (var section in new[] { "tabs", "folders", "history", "archivedTabs", "splitGroups" })
            Assert.Empty(space[section]!.AsArray());
        Assert.Null(space["selectedTabID"]);
        var metadata = space.DeepClone(); metadata["name"] = "Not the owner";
        Assert.Equal("borrowed_profile_requires_owner", Assert.Throws<BrowserRuleException>(() =>
            child.Commit(Bytes(new JsonObject {
                ["version"] = 1,
                ["spaces"] = new JsonArray(new JsonObject { ["id"] = space["id"]!.DeepClone(), ["metadata"] = metadata })
            }))).Code);
        Assert.Equal(1UL, child.Revision);
        var fabricated = projected.DeepClone(); fabricated["coreWorkspaceKind"] = "temporary";
        Assert.Equal("borrowed_source_required", Assert.Throws<BrowserRuleException>(() =>
            new NativeSessionAuthority(Bytes(fabricated))).Code);
        Assert.Throws<BrowserRuleException>(() => owner.CreateBorrowed(Guid.Parse(source["id"]!["rawValue"]!.GetValue<string>()), Guid.NewGuid()));
    }

    [Fact]
    public void BorrowedPolicyRefreshPreservesLocalRecordsAndRejectsPreparedEditsAfterOwnerChanges() {
        var session = SavedSession().Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session)); var child = Borrow(owner, session);
        using var device = new TestDevice(owner);
        var initial = JsonNode.Parse(child.Checkpoint().Read("core"))!;
        var localTab = session["spaces"]![0]!["tabs"]![0]!.DeepClone();
        localTab["folderID"] = null; localTab["splitGroupID"] = null; localTab["placement"] = "current";
        byte[] Local(JsonNode tab) => Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject {
                ["id"] = initial["spaces"]![0]!["id"]!.DeepClone(),
                ["tabs"] = new JsonObject { ["replace"] = new JsonArray(tab.DeepClone()) }
            })
        });
        child.Commit(Local(localTab));
        var local = JsonNode.Parse(child.Checkpoint().Read("core"))!;
        device.Send(new SetSpaceIdentity(device.Workspace, SpaceId(session["spaces"]![0]!), "New canonical name", "book", SpaceAccent.Teal));
        Assert.Equal("stale_borrowed_source", Assert.Throws<BrowserRuleException>(() => child.Commit(Local(localTab))).Code);
        var refresh = child.PrepareBorrowedRefresh();
        Assert.Equal(2UL, child.Revision);
        refresh.Commit();
        var after = JsonNode.Parse(child.Checkpoint().Read("core"))!;
        Assert.True(JsonNode.DeepEquals(local["spaces"]![0]!["tabs"], after["spaces"]![0]!["tabs"]));
        Assert.Equal("New canonical name", after["spaces"]![0]!["name"]!.GetValue<string>());

        // A tab the borrowed workspace opens stays with it.
        var borrowed = device.Attach(child);
        device.Send(new OpenTab(borrowed, Guid.NewGuid(), SpaceId(session["spaces"]![0]!), Guid.NewGuid(),
            new TabContent("https://example.org/", null, "Prepared locally", null), TabPlacement.Current, null, false));
        Assert.Contains("Prepared locally", System.Text.Encoding.UTF8.GetString(child.Checkpoint().Read("core")));
        Assert.DoesNotContain("Prepared locally", System.Text.Encoding.UTF8.GetString(owner.Checkpoint().Read("core")));
    }

    [Fact]
    public void DeletingOrReleasingTheOwnerRevokesBorrowedCommandsWithoutRewritingTheirRecords() {
        var session = SavedSession().Document["session"]!;
        var extra = session["spaces"]![0]!.DeepClone();
        extra["id"] = SwiftId(Guid.NewGuid()); extra["profile"]!["id"] = Guid.NewGuid().ToString();
        extra["tabs"] = new JsonArray(); extra["selectedTabID"] = null;
        session["spaces"]!.AsArray().Add(extra);
        var owner = new NativeSessionAuthority(Bytes(session)); var child = Borrow(owner, session);
        using var device = new TestDevice(owner);
        var old = child.Checkpoint();
        var prepared = child.PrepareBorrowedRefresh();
        device.Send(new BeginDeletingSpace(device.Workspace, Guid.NewGuid(), SpaceId(session["spaces"]![0]!), Guid.NewGuid()));
        Assert.Equal("profile_lease_revoked", Assert.Throws<BrowserRuleException>(() => prepared.Commit()).Code);
        Assert.Equal("profile_lease_revoked", Assert.Throws<BrowserRuleException>(() => child.PrepareBorrowedRefresh()).Code);
        Assert.Equal(old.Read("core"), child.Checkpoint().Read("core"));

        var anotherOwner = new NativeSessionAuthority(Bytes(session)); var another = Borrow(anotherOwner, session);
        var pending = another.PrepareBorrowedRefresh();
        anotherOwner.Release();
        Assert.Equal("profile_lease_revoked", Assert.Throws<BrowserRuleException>(() => pending.Commit()).Code);
        Assert.Equal(1UL, another.Revision);
    }
}
