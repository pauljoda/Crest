using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static byte[] Bytes(JsonNode value) => Encoding.UTF8.GetBytes(value.ToJsonString());
    private static byte[] RenameDelta(JsonNode session, string title) {
        var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!.DeepClone(); tab["title"] = title;
        return Bytes(new JsonObject {
            ["version"] = 1,
            ["spaces"] = new JsonArray(new JsonObject {
                ["id"] = space["id"]!.DeepClone(),
                ["tabs"] = new JsonObject { ["remove"] = new JsonArray(), ["upsert"] = new JsonArray(tab) }
            })
        });
    }

    [Theory]
    [InlineData("space.future", BrowserRuleCodes.UnknownSpaceCommand)]
    [InlineData("history.future", BrowserRuleCodes.UnknownHistoryCommand)]
    [InlineData("records.future", BrowserRuleCodes.UnknownRecordCommand)]
    [InlineData("transient.future", BrowserRuleCodes.UnknownTransientCommand)]
    [InlineData("preferences.future", BrowserRuleCodes.UnknownPreferenceCommand)]
    public void UnknownOperationFamiliesKeepTheirSpecificErrors(string operation, string expectedCode) {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var request = new JsonObject {
            ["version"] = 1,
            ["operation"] = operation,
            ["spaceId"] = fixture.Space.ToString(),
            ["profileId"] = space["profile"]!["id"]!.DeepClone(),
            ["arguments"] = new JsonObject { ["requestId"] = Guid.NewGuid().ToString() },
            ["now"] = 800000001.0
        };

        var error = Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(1, Bytes(request)));
        Assert.Equal(expectedCode, error.Code);
    }
    [Fact]
    public void DurableReplacementReservesPublicationAndCancellationKeepsTheAcceptedRevision() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var original = authority.Checkpoint(1).Read("core");
        using (var cancelled = authority.ReserveReplacement(1, RenameDelta(session, "Not saved"))) {
            Assert.Equal(original, authority.Checkpoint(1).Read("core"));
            Assert.Throws<BrowserRuleException>(() => authority.Commit(1, RenameDelta(session, "Racing edit")));
            Assert.Throws<BrowserRuleException>(() => authority.ReserveReplacement(1, RenameDelta(session, "Racing merge")));
        }
        Assert.Equal(1UL, authority.Revision);
        using var accepted = authority.ReserveReplacement(1, RenameDelta(session, "Durable"));
        var persisted = accepted.Checkpoint.Read("core");
        Assert.Equal(2UL, accepted.Commit());
        Assert.Equal(persisted, authority.Checkpoint(2).Read("core"));
        Assert.Throws<BrowserRuleException>(() => accepted.Commit());
        authority.Commit(2, RenameDelta(session, "Next local edit"));
        Assert.Equal(3UL, authority.Revision);
    }

    [Fact]
    public void NativeAuthorityRejectsStaleEditsAndKeepsEarlierCheckpointStable() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var before = authority.Checkpoint(1);
        var original = before.Read("core");
        authority.Commit(1, RenameDelta(session, "Updated native title"));
        Assert.Equal(original, before.Read("core"));
        var after = JsonNode.Parse(authority.Checkpoint(2).Read("core"))!;
        Assert.Equal("Updated native title", after["spaces"]![0]!["tabs"]![0]!["title"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0]!["branding"], after["spaces"]![0]!["branding"]));
        Assert.Empty(after["spaces"]![0]!["history"]!.AsArray());
        Assert.Throws<BrowserRuleException>(() => authority.Commit(1, RenameDelta(session, "Stale")));
        Assert.Equal(2UL, authority.Revision);
    }
    [Fact]
    public void NativeWorkspacePairRejectsBothWhenDestinationRevisionIsStale() {
        var session = SavedSession().Document["session"]!;
        var source = new NativeSessionAuthority(Bytes(session));
        var destination = new NativeSessionAuthority(Bytes(session));
        var sourceBefore = source.Checkpoint(1).Read("core");
        destination.Commit(1, RenameDelta(session, "Concurrent destination edit"));
        Assert.Throws<BrowserRuleException>(() => NativeSessionAuthority.CommitPair(
            source, 1, RenameDelta(session, "Source proposal"), destination, 1, RenameDelta(session, "Destination proposal")));
        Assert.Equal(1UL, source.Revision);
        Assert.Equal(sourceBefore, source.Checkpoint(1).Read("core"));
        var result = NativeSessionAuthority.CommitPair(
            source, 1, RenameDelta(session, "Source accepted"), destination, 2, RenameDelta(session, "Destination accepted"));
        Assert.Equal((2UL, 3UL), result);
    }

    [Fact]
    public void NativeCommandsPrepareWithoutMutationAndRejectConcurrentCommits() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        byte[] Request(string title) => Bytes(new JsonObject {
            ["version"] = 1,
            ["spaceId"] = fixture.Space.ToString(),
            ["profileId"] = space["profile"]!["id"]!.DeepClone(),
            ["operation"] = "tab.rename",
            ["now"] = 800000001.0,
            ["arguments"] = new JsonObject { ["tabId"] = fixture.Tab.ToString(), ["title"] = title },
        });
        var before = authority.Checkpoint(1).Read("core");
        var first = authority.PrepareCommand(1, Request("Accepted"));
        var competing = authority.PrepareCommand(1, Request("Stale"));
        Assert.Equal(before, authority.Checkpoint(1).Read("core"));
        Assert.Null(JsonNode.Parse(first.Output)!["space"]!["selectedTabID"]);
        Assert.Equal(2UL, first.Commit());
        Assert.Throws<BrowserRuleException>(() => competing.Commit());
        Assert.Throws<BrowserRuleException>(() => first.Commit());
        var checkpoint = authority.Checkpoint(2);
        var saved = JsonNode.Parse(checkpoint.Read("core"))!["spaces"]![0]!;
        Assert.Equal("Accepted", saved["tabs"]![0]!["customTitle"]!.GetValue<string>());
        Assert.Null(saved["selectedTabID"]);
        Assert.True(JsonNode.DeepEquals(space["history"], JsonNode.Parse(checkpoint.Read(fixture.Space.ToString()))));
        Assert.True(JsonNode.DeepEquals(space["branding"], saved["branding"]));
    }

    /// A command in `target`, the session's first Space unless named, issued
    /// from `window` when one is given.
    private static byte[] SpaceCommand(JsonNode session, string operation, JsonObject arguments, JsonNode? target = null,
        Guid? window = null) {
        target ??= session["spaces"]![0]!;
        var request = new JsonObject {
            ["version"] = 1,
            ["operation"] = operation,
            ["arguments"] = arguments,
            ["spaceId"] = target["id"]!.DeepClone(),
            ["profileId"] = target["profile"]!["id"]!.DeepClone(),
            ["now"] = 800000002.0
        };
        return Bytes(window is { } issuer ? IssuedFrom(request, issuer) : request);
    }

    [Fact]
    public void OwnedTabCopiesUseCurrentRecordsAndRejectAStalePublication() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var core = new NativeSessionAuthority(Bytes(session));
        JsonObject Arguments(Guid id) => new() {
            ["tabId"] = fixture.Tab.ToString(),
            ["ids"] = new JsonArray(id.ToString()),
            ["copyObservations"] = new JsonArray(new JsonObject {
                ["tabId"] = fixture.Tab.ToString(),
                ["url"] = "https://example.com/live-child",
                ["title"] = "Live title"
            })
        };
        var rejected = core.PrepareCommand(1, SpaceCommand(session, "tab.copy", Arguments(Guid.NewGuid())));
        core.PrepareCommand(1, SpaceCommand(session, "tab.rename", new() { ["tabId"] = fixture.Tab.ToString(), ["title"] = "Latest name" })).Commit();
        Assert.Throws<BrowserRuleException>(() => rejected.Commit());
        var id = Guid.NewGuid();
        var accepted = core.PrepareCommand(2, SpaceCommand(session, "tab.copy", Arguments(id)));
        accepted.Commit();
        var space = JsonNode.Parse(core.Checkpoint(3).Read("core"))!["spaces"]![0]!;
        var copy = space["tabs"]!.AsArray().Single(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>()) == id)!;
        var original = space["tabs"]!.AsArray().Single(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>()) == fixture.Tab)!;
        Assert.Equal("Latest name", copy["customTitle"]!.GetValue<string>());
        Assert.Equal("Live title", copy["title"]!.GetValue<string>());
        Assert.Equal("https://example.com/live-child", copy["url"]!.GetValue<string>());
        Assert.Equal("current", copy["placement"]!.GetValue<string>());
        Assert.Null(copy["splitGroupID"]); Assert.Null(copy["savedURL"]);
        Assert.True(JsonNode.DeepEquals(original["iconAccent"], copy["iconAccent"]));
        Assert.Equal("saved", original["placement"]!.GetValue<string>());
        Assert.Equal("https://example.com/article#one", original["url"]!.GetValue<string>());
        Assert.Single(JsonNode.Parse(accepted.Output)!["copies"]!.AsArray());
    }

    [Fact]
    public void OwnedSplitLinkCopiesMetadataAndMovesOrDissolvesTheAcceptedGroupAtomically() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!; var original = space["tabs"]![0]!;
        var peer = original.DeepClone(); peer["id"] = SwiftId(Guid.NewGuid());
        space["tabs"]!.AsArray().Add(peer);
        space["splitGroups"] = new JsonArray(new JsonObject {
            ["id"] = original["splitGroupID"]!.DeepClone(),
            ["customTitle"] = "Saved pair",
            ["titleModifiedAt"] = 800000000.0
        });
        var core = new NativeSessionAuthority(Bytes(session));
        JsonObject LinkArgs(Guid id) => new() {
            ["targetId"] = fixture.Tab.ToString(),
            ["ids"] = new JsonArray(Enumerable.Range(0, 6).Select(_ => (JsonNode)JsonValue.Create(Guid.NewGuid().ToString())!).ToArray()),
            ["tab"] = new JsonObject {
                ["id"] = SwiftId(id),
                ["title"] = "Link",
                ["url"] = "https://example.org/link",
                ["placement"] = "current",
                ["lastActivatedAt"] = 800000002.0
            }
        };
        var linked = Guid.NewGuid();
        var command = core.PrepareCommand(1, SpaceCommand(session, "split.open_link", LinkArgs(linked)));
        command.Commit();
        var output = JsonNode.Parse(command.Output)!; var updated = output["space"]!;
        Assert.Equal(5, updated["tabs"]!.AsArray().Count);
        Assert.Equal(2, output["copies"]!.AsArray().Count);
        var group = updated["tabs"]!.AsArray().Single(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>()) == linked)!["splitGroupID"]!;
        Assert.NotEqual(original["splitGroupID"]!.ToJsonString(), group.ToJsonString());
        var groupId = Guid.Parse(group["rawValue"]!.GetValue<string>());
        Assert.Equal("Saved pair", updated["splitGroups"]!.AsArray().Single(g => Guid.Parse(g!["id"]!["rawValue"]!.GetValue<string>()) == groupId)!["customTitle"]!.GetValue<string>());
        var before = core.Checkpoint(2).Read("core");
        Assert.Throws<BrowserRuleException>(() => core.PrepareCommand(2, SpaceCommand(session, "split.move", new() { ["groupId"] = groupId.ToString(), ["placement"] = "pinned" })));
        Assert.Equal(before, core.Checkpoint(2).Read("core"));
        core.PrepareCommand(2, SpaceCommand(session, "split.move", new() { ["groupId"] = groupId.ToString(), ["placement"] = "saved", ["folderId"] = original["folderID"]!["rawValue"]!.DeepClone() })).Commit();
        core.PrepareCommand(3, SpaceCommand(session, "split.dissolve", new() { ["groupId"] = groupId.ToString() })).Commit();
        var final = JsonNode.Parse(core.Checkpoint(4).Read("core"))!["spaces"]![0]!;
        Assert.Equal(5, final["tabs"]!.AsArray().Count);
        Assert.All(final["tabs"]!.AsArray(), t => Assert.Equal("saved", t!["placement"]!.GetValue<string>()));
        Assert.Single(final["splitGroups"]!.AsArray());
        Assert.Equal(2, final["tabs"]!.AsArray().Count(t => t!["splitGroupID"] is not null));
    }

    [Fact]
    public void SpaceCommandsPreserveCollectionsAndCannotApplyToReplacedProfiles() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var original = authority.Checkpoint(1);
        var pending = authority.PrepareCommand(1, SpaceCommand(session, "space.identity", new() { ["name"] = "  Research  ", ["symbol"] = "  ", ["accent"] = "teal" }));
        Assert.Equal(1UL, authority.Revision);
        var projection = JsonNode.Parse(pending.Output)!["session"]!;
        Assert.Empty(projection["spaces"]![0]!["tabs"]!.AsArray());
        pending.Commit();
        var saved = JsonNode.Parse(authority.Checkpoint(2).Read("core"))!;
        Assert.Equal("Research", saved["spaces"]![0]!["name"]!.GetValue<string>());
        Assert.Equal("square.grid.2x2", saved["spaces"]![0]!["symbol"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(original.Read("core"))!["spaces"]![0]!["tabs"], saved["spaces"]![0]!["tabs"]));
        Assert.Equal(original.Read(fixture.Space.ToString()), authority.Checkpoint(2).Read(fixture.Space.ToString()));
        var invalid = JsonNode.Parse(SpaceCommand(session, "space.access", new() { ["value"] = "open" }))!;
        invalid["profileId"] = Guid.NewGuid().ToString();
        Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(2, Bytes(invalid)));
        Assert.Equal(2UL, authority.Revision);
    }

    [Fact]
    public void SpaceRemovalRetainsOtherSpacesAndRejectsTheLastSpace() {
        var session = SavedSession().Document["session"]!;
        var second = session["spaces"]![0]!.DeepClone();
        second["id"] = SwiftId(Guid.NewGuid()); second["profile"]!["id"] = Guid.NewGuid().ToString();
        second["tabs"] = new JsonArray(); second["selectedTabID"] = null;
        session["spaces"]!.AsArray().Add(second);
        session["defaultSpaceID"] = session["spaces"]![0]!["id"]!.DeepClone();
        var authority = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(authority);
        var window = device.Showing(session);
        var args = new JsonObject { ["operationID"] = Guid.NewGuid().ToString("D") };
        authority.PrepareCommand(1, SpaceCommand(session, "space.deletion.begin", args.DeepClone().AsObject(), window: window)).Commit();
        Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(2,
            SpaceCommand(session, "space.deletion.begin", new() { ["operationID"] = Guid.NewGuid().ToString("D") }, second)));
        var command = authority.PrepareCommand(2, SpaceCommand(session, "space.remove", args.DeepClone().AsObject()));
        command.Commit();
        var output = JsonNode.Parse(command.Output)!;
        var projection = output["session"]!;
        Assert.Single(projection["spaces"]!.AsArray());
        // The window showing the removed Space moves to the one that takes its
        // place; the launch Space follows. Neither is stored as a selection.
        Assert.Equal(SpaceId(second), device.Space(window));
        Assert.Null(projection["selectedSpaceID"]);
        Assert.True(JsonNode.DeepEquals(second["id"], projection["defaultSpaceID"]));
        Assert.Null(projection["spaceDeletions"]);
        Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(3,
            SpaceCommand(projection, "space.deletion.begin", args.DeepClone().AsObject())));
    }

    [Fact]
    public void DeletionIntentIsDurableBeforeCleanupAndCannotBeLostToStaleEdits() {
        var session = SavedSession().Document["session"]!;
        var second = session["spaces"]![0]!.DeepClone();
        second["id"] = SwiftId(Guid.NewGuid()); second["profile"]!["id"] = Guid.NewGuid().ToString();
        second["tabs"] = new JsonArray(); second["selectedTabID"] = null;
        session["spaces"]!.AsArray().Add(second);
        var authority = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(authority);
        var window = device.Showing(session);
        var args = new JsonObject { ["operationID"] = Guid.NewGuid().ToString("D") };
        var command = authority.PrepareCommand(1, SpaceCommand(session, "space.deletion.begin", args.DeepClone().AsObject(), window: window));
        using (var cancelled = command.Reserve()) {
            Assert.Equal(1UL, authority.Revision);
            Assert.Null(JsonNode.Parse(authority.Checkpoint(1).Read("core"))!["spaceDeletions"]);
            Assert.Throws<BrowserRuleException>(() => authority.Commit(1, RenameDelta(session, "Racing write")));
        }
        Assert.Equal(SpaceId(session["spaces"]![0]!), device.Space(window));
        using var saved = command.Reserve();
        var bytes = saved.Checkpoint.Read("core");
        saved.Commit();
        // The window leaves the Space being deleted for the one that takes its place.
        Assert.Equal(SpaceId(second), device.Space(window));
        var restarted = new NativeSessionAuthority(bytes);
        var restored = JsonNode.Parse(bytes)!;
        Assert.Single(restored["spaceDeletions"]!.AsArray());
        Assert.Null(restored["selectedSpaceID"]);
        Assert.Throws<BrowserRuleException>(() => restarted.Commit(1, RenameDelta(restored, "Late page callback")));
        Assert.Throws<BrowserRuleException>(() => restarted.PrepareCommand(1,
            SpaceCommand(restored, "space.identity", new() { ["name"] = "Revived", ["symbol"] = "globe", ["accent"] = "teal" })));
        Assert.Throws<BrowserRuleException>(() => restarted.PrepareCommand(1,
            SpaceCommand(restored, "space.remove", new() { ["operationID"] = Guid.NewGuid().ToString() })));
        var completion = restarted.PrepareCommand(1, SpaceCommand(restored, "space.remove", args.DeepClone().AsObject()));
        using var finishing = completion.Reserve();
        Assert.Null(JsonNode.Parse(finishing.Checkpoint.Read("core"))!["spaceDeletions"]);
        finishing.Commit();
    }

    [Fact]
    public void PrivateSpaceCreationEnforcesPrivateDefaultsAndBorrowedWorkspaceCannotCreate() {
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
        var deletion = new JsonObject { ["operationID"] = Guid.NewGuid().ToString("D") };
        authority.PrepareCommand(2, SpaceCommand(projection, "space.deletion.begin", deletion)).Commit();
        var fresh = template.DeepClone();
        fresh["id"] = SwiftId(Guid.NewGuid()); fresh["profile"]!["id"] = Guid.NewGuid().ToString("D");
        var reset = authority.PrepareCommand(3, SpaceCommand(projection, "space.reset_private", new() { ["template"] = fresh }));
        reset.Commit();
        var cleared = JsonNode.Parse(reset.Output)!["session"]!;
        Assert.Single(cleared["spaces"]!.AsArray());
        Assert.Null(cleared["spaceDeletions"]);
        Assert.Equal("Private", cleared["spaces"]![0]!["name"]!.GetValue<string>());
        var borrowed = Borrow(authority, cleared);
        Assert.Throws<BrowserRuleException>(() => borrowed.PrepareCommand(1,
            SpaceCommand(session, "space.identity", new() { ["name"] = "Changed", ["symbol"] = "globe", ["accent"] = "teal" })));
    }

    [Fact]
    public void SpaceReorderingUsesOriginalOffsetsAndClampsTheInsertionPoint() {
        Assert.Equal(new[] { "b", "d", "a", "c" }, SpaceOrganizationPolicy.Move(new[] { "a", "b", "c", "d" }, [2, 0, 2, -1, 9], 4));
        Assert.Equal(new[] { "c", "a", "b" }, SpaceOrganizationPolicy.Move(new[] { "a", "b", "c" }, [2], int.MinValue));
    }
}
