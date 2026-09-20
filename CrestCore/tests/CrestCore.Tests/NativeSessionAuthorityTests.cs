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
}
