using System.Text;
using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static byte[] Bytes(JsonNode value) => Encoding.UTF8.GetBytes(value.ToJsonString());
    private static byte[] Selection(JsonNode session) => Bytes(new JsonObject
    {
        ["selectedSpaceID"] = session["selectedSpaceID"]!.DeepClone(),
        ["selectedTabs"] = new JsonArray(session["spaces"]!.AsArray().Select(s => (JsonNode)new JsonObject
        { ["spaceID"] = s!["id"]!.DeepClone(), ["tabID"] = s["selectedTabID"]?.DeepClone() }).ToArray())
    });
    private static byte[] RenameDelta(JsonNode session, string title)
    {
        var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!.DeepClone(); tab["title"] = title;
        return Bytes(new JsonObject { ["version"] = 1, ["spaces"] = new JsonArray(new JsonObject
        { ["id"] = space["id"]!.DeepClone(), ["tabs"] = new JsonObject
        { ["remove"] = new JsonArray(), ["upsert"] = new JsonArray(tab) } }) });
    }
    [Fact]
    public void NativeAuthorityRejectsStaleEditsAndKeepsEarlierCheckpointStable()
    {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var selection = Selection(session);
        var before = authority.Checkpoint(1, selection);
        var original = before.Read("core");
        authority.Commit(1, RenameDelta(session, "Updated native title"));
        Assert.Equal(original, before.Read("core"));
        var after = JsonNode.Parse(authority.Checkpoint(2, selection).Read("core"))!;
        Assert.Equal("Updated native title", after["spaces"]![0]!["tabs"]![0]!["title"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0]!["branding"], after["spaces"]![0]!["branding"]));
        Assert.Empty(after["spaces"]![0]!["history"]!.AsArray());
        Assert.Throws<BrowserRuleException>(() => authority.Commit(1, RenameDelta(session, "Stale")));
        Assert.Equal(2UL, authority.Revision);
    }
    [Fact]
    public void NativeWorkspacePairRejectsBothWhenDestinationRevisionIsStale()
    {
        var session = SavedSession().Document["session"]!;
        var source = new NativeSessionAuthority(Bytes(session));
        var destination = new NativeSessionAuthority(Bytes(session));
        var sourceBefore = source.Checkpoint(1, Selection(session)).Read("core");
        destination.Commit(1, RenameDelta(session, "Concurrent destination edit"));
        Assert.Throws<BrowserRuleException>(() => NativeSessionAuthority.CommitPair(
            source, 1, RenameDelta(session, "Source proposal"), destination, 1, RenameDelta(session, "Destination proposal")));
        Assert.Equal(1UL, source.Revision);
        Assert.Equal(sourceBefore, source.Checkpoint(1, Selection(session)).Read("core"));
        var result = NativeSessionAuthority.CommitPair(
            source, 1, RenameDelta(session, "Source accepted"), destination, 2, RenameDelta(session, "Destination accepted"));
        Assert.Equal((2UL, 3UL), result);
    }

    [Fact]
    public void NativeCommandsPrepareWithoutMutationAndRejectConcurrentCommits()
    {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var window = JsonNode.Parse(Selection(session))!;
        window["selectedTabs"]![0]!["tabID"] = null;
        byte[] Request(string title) => Bytes(new JsonObject
        {
            ["version"] = 1, ["spaceId"] = fixture.Space.Value.ToString(),
            ["profileId"] = space["profile"]!["id"]!.DeepClone(), ["window"] = window.DeepClone(),
            ["operation"] = "tab.rename", ["now"] = 800000001.0,
            ["arguments"] = new JsonObject { ["tabId"] = fixture.Tab.Value.ToString(), ["title"] = title },
        });
        var before = authority.Checkpoint(1, Selection(session)).Read("core");
        var first = authority.PrepareCommand(1, Request("Accepted"));
        var competing = authority.PrepareCommand(1, Request("Stale"));
        Assert.Equal(before, authority.Checkpoint(1, Selection(session)).Read("core"));
        Assert.Null(JsonNode.Parse(first.Output)!["space"]!["selectedTabID"]);
        Assert.Equal(2UL, first.Commit());
        Assert.Throws<BrowserRuleException>(() => competing.Commit());
        Assert.Throws<BrowserRuleException>(() => first.Commit());
        var checkpoint = authority.Checkpoint(2, Bytes(window));
        var saved = JsonNode.Parse(checkpoint.Read("core"))!["spaces"]![0]!;
        Assert.Equal("Accepted", saved["tabs"]![0]!["customTitle"]!.GetValue<string>());
        Assert.Null(saved["selectedTabID"]);
        Assert.True(JsonNode.DeepEquals(space["history"], JsonNode.Parse(checkpoint.Read(fixture.Space.Value.ToString()))));
        Assert.True(JsonNode.DeepEquals(space["branding"], saved["branding"]));
    }

    private static byte[] SpaceCommand(JsonNode session, string operation, JsonObject arguments, JsonNode? target = null)
    {
        target ??= session["spaces"]![0]!;
        return Bytes(new JsonObject
        {
            ["version"] = 1, ["operation"] = operation, ["arguments"] = arguments,
            ["spaceId"] = target["id"]!.DeepClone(), ["profileId"] = target["profile"]!["id"]!.DeepClone(),
            ["window"] = JsonNode.Parse(Selection(session)), ["now"] = 800000002.0
        });
    }

    [Fact]
    public void SpaceCommandsPreserveCollectionsAndCannotApplyToReplacedProfiles()
    {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var original = authority.Checkpoint(1, Selection(session));
        var pending = authority.PrepareCommand(1, SpaceCommand(session, "space.identity", new()
        { ["name"] = "  Research  ", ["symbol"] = "  ", ["accent"] = "teal" }));
        Assert.Equal(1UL, authority.Revision);
        var projection = JsonNode.Parse(pending.Output)!["session"]!;
        Assert.Empty(projection["spaces"]![0]!["tabs"]!.AsArray());
        pending.Commit();
        var saved = JsonNode.Parse(authority.Checkpoint(2, Selection(session)).Read("core"))!;
        Assert.Equal("Research", saved["spaces"]![0]!["name"]!.GetValue<string>());
        Assert.Equal("square.grid.2x2", saved["spaces"]![0]!["symbol"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(original.Read("core"))!["spaces"]![0]!["tabs"], saved["spaces"]![0]!["tabs"]));
        Assert.Equal(original.Read(fixture.Space.Value.ToString()), authority.Checkpoint(2, Selection(session)).Read(fixture.Space.Value.ToString()));
        var invalid = JsonNode.Parse(SpaceCommand(session, "space.access", new() { ["value"] = "open" }))!;
        invalid["profileId"] = Guid.NewGuid().ToString();
        Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(2, Bytes(invalid)));
        Assert.Equal(2UL, authority.Revision);
    }

    [Fact]
    public void SpaceRemovalRetainsOtherSpacesAndRejectsTheLastSpace()
    {
        var session = SavedSession().Document["session"]!;
        var second = session["spaces"]![0]!.DeepClone();
        second["id"] = SwiftId(Guid.NewGuid()); second["profile"]!["id"] = Guid.NewGuid().ToString();
        second["tabs"] = new JsonArray(); second["selectedTabID"] = null;
        session["spaces"]!.AsArray().Add(second);
        session["defaultSpaceID"] = session["spaces"]![0]!["id"]!.DeepClone();
        var authority = new NativeSessionAuthority(Bytes(session));
        var command = authority.PrepareCommand(1, SpaceCommand(session, "space.remove", new()));
        command.Commit();
        var projection = JsonNode.Parse(command.Output)!["session"]!;
        Assert.Single(projection["spaces"]!.AsArray());
        Assert.True(JsonNode.DeepEquals(second["id"], projection["selectedSpaceID"]));
        Assert.True(JsonNode.DeepEquals(second["id"], projection["defaultSpaceID"]));
        Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(2, SpaceCommand(projection, "space.remove", new())));
    }

    [Fact]
    public void PrivateSpaceCreationEnforcesPrivateDefaultsAndBorrowedWorkspaceCannotCreate()
    {
        var session = SavedSession().Document["session"]!;
        var template = session["spaces"]![0]!.DeepClone();
        template["id"] = SwiftId(Guid.NewGuid()); template["profile"]!["id"] = Guid.NewGuid().ToString();
        template["folders"] = new JsonArray(); template["history"] = new JsonArray(); template["archivedTabs"] = new JsonArray();
        template["tabs"]![0]!["id"] = SwiftId(Guid.NewGuid()); template["tabs"]![0]!["url"] = null;
        template["selectedTabID"] = template["tabs"]![0]!["id"]!.DeepClone();
        session["coreWorkspaceKind"] = "private";
        var authority = new NativeSessionAuthority(Bytes(session));
        var command = authority.PrepareCommand(1, SpaceCommand(session, "space.create", new() { ["template"] = template }));
        command.Commit();
        var projection = JsonNode.Parse(command.Output)!["session"]!;
        var added = projection["spaces"]![1]!;
        Assert.Equal("Private 2", added["name"]!.GetValue<string>());
        Assert.Equal("duckDuckGo", added["browsingPreferences"]!["selectedSearchProviderID"]!.GetValue<string>());
        Assert.Equal("never", added["browsingPreferences"]!["currentTabCleanupPolicy"]!.GetValue<string>());
        Assert.False(added["credentialPreferences"]!["syncsCrestPasswordsWithICloud"]!.GetValue<bool>());
        Assert.Null(projection["coreWorkspaceKind"]);
        session["coreWorkspaceKind"] = "temporary";
        var borrowed = new NativeSessionAuthority(Bytes(session));
        Assert.Throws<BrowserRuleException>(() => borrowed.PrepareCommand(1,
            SpaceCommand(session, "space.identity", new() { ["name"] = "Changed", ["symbol"] = "globe", ["accent"] = "teal" })));
    }

    [Fact]
    public void SpaceReorderingUsesOriginalOffsetsAndClampsTheInsertionPoint()
    {
        Assert.Equal(new[] { "b", "d", "a", "c" }, SpaceOrganizationPolicy.Move(new[] { "a", "b", "c", "d" }, [2, 0, 2, -1, 9], 4));
        Assert.Equal(new[] { "c", "a", "b" }, SpaceOrganizationPolicy.Move(new[] { "a", "b", "c" }, [2], int.MinValue));
    }
}
