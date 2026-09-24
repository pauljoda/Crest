using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
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

        var error = Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(Bytes(request)));
        Assert.Equal(expectedCode, error.Code);
    }
    [Fact]
    public void DurableReplacementReservesPublicationAndCancellationKeepsTheAcceptedRevision() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var original = authority.Checkpoint().Read("core");
        using (var cancelled = authority.ReserveReplacement(RenameDelta(session, "Not saved"))) {
            Assert.Equal(original, authority.Checkpoint().Read("core"));
            Assert.Throws<BrowserRuleException>(() => authority.Commit(RenameDelta(session, "Racing edit")));
            Assert.Throws<BrowserRuleException>(() => authority.ReserveReplacement(RenameDelta(session, "Racing merge")));
        }
        Assert.Equal(1UL, authority.Revision);
        using var accepted = authority.ReserveReplacement(RenameDelta(session, "Durable"));
        var persisted = accepted.Checkpoint.Read("core");
        accepted.Commit();
        Assert.Equal(2UL, authority.Revision);
        Assert.Equal(persisted, authority.Checkpoint().Read("core"));
        Assert.Throws<BrowserRuleException>(() => accepted.Commit());
        authority.Commit(RenameDelta(session, "Next local edit"));
        Assert.Equal(3UL, authority.Revision);
    }

    [Fact]
    public void NativeAuthorityKeepsEarlierCheckpointStable() {
        var session = SavedSession().Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var before = authority.Checkpoint();
        var original = before.Read("core");
        authority.Commit(RenameDelta(session, "Updated native title"));
        Assert.Equal(original, before.Read("core"));
        var after = JsonNode.Parse(authority.Checkpoint().Read("core"))!;
        Assert.Equal("Updated native title", after["spaces"]![0]!["tabs"]![0]!["title"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0]!["branding"], after["spaces"]![0]!["branding"]));
        Assert.Empty(after["spaces"]![0]!["history"]!.AsArray());
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
    public void ALinkOpenedInADurableSplitCopiesItsMetadataAndTheSplitMovesOrDissolvesWhole() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!; var original = space["tabs"]![0]!;
        var peer = original.DeepClone(); peer["id"] = SwiftId(Guid.NewGuid());
        space["tabs"]!.AsArray().Add(peer);
        space["splitGroups"] = new JsonArray(new JsonObject {
            ["id"] = original["splitGroupID"]!.DeepClone(),
            ["customTitle"] = "Saved pair",
            ["titleModifiedAt"] = 800000000.0
        });
        var savedGroup = Guid.Parse(original["splitGroupID"]!["rawValue"]!.GetValue<string>());
        var folder = Guid.Parse(original["folderID"]!["rawValue"]!.GetValue<string>());
        var core = new NativeSessionAuthority(Bytes(session));
        using var device = new TestDevice(core);
        var window = device.Showing(session);
        var linked = Guid.NewGuid();

        var changes = device.Send(new OpenLinkInSplit(device.Workspace, window, fixture.Space, linked, fixture.Tab,
            "https://example.org/link", "Link", []));

        // The saved pair stays; open copies of it and the link make the split.
        Assert.Equal(2, changes.OfType<TabCopied>().Count());
        var updated = core.Current.Spaces[0];
        Assert.Equal(5, updated.Tabs.Count);
        var group = updated.Tabs.Single(tab => tab.Id == linked).SplitGroupId!.Value;
        Assert.NotEqual(savedGroup, group);
        Assert.Equal("Saved pair", updated.SplitGroups.Single(metadata => metadata.Id == group).CustomTitle);
        Assert.Equal(linked, device.Tab(window, fixture.Space));
        var before = core.Current;
        Assert.IsType<InvalidFolderPlacement>(Assert.Throws<Rejected>(() =>
            device.Send(new MoveSplit(device.Workspace, fixture.Space, group, TabPlacement.Pinned, null, null))).Rejection);
        Assert.Same(before, core.Current);
        device.Send(new MoveSplit(device.Workspace, fixture.Space, group, TabPlacement.Saved, folder, null));
        device.Send(new DissolveSplit(device.Workspace, fixture.Space, group));
        var final = core.Current.Spaces[0];
        Assert.Equal(5, final.Tabs.Count);
        Assert.All(final.Tabs, tab => Assert.Equal(TabPlacement.Saved, tab.Placement));
        Assert.Equal(savedGroup, Assert.Single(final.SplitGroups).Id);
        Assert.Equal(2, final.Tabs.Count(tab => tab.SplitGroupId is not null));
    }

    [Fact]
    public void SpaceCommandsPreserveCollectionsAndCannotApplyToReplacedProfiles() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var authority = new NativeSessionAuthority(Bytes(session));
        var original = authority.Checkpoint();
        var pending = authority.PrepareCommand(SpaceCommand(session, "space.identity", new() { ["name"] = "  Research  ", ["symbol"] = "  ", ["accent"] = "teal" }));
        Assert.Equal(1UL, authority.Revision);
        var projection = JsonNode.Parse(pending.Output)!["session"]!;
        Assert.Empty(projection["spaces"]![0]!["tabs"]!.AsArray());
        pending.Commit();
        var saved = JsonNode.Parse(authority.Checkpoint().Read("core"))!;
        Assert.Equal("Research", saved["spaces"]![0]!["name"]!.GetValue<string>());
        Assert.Equal("square.grid.2x2", saved["spaces"]![0]!["symbol"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(original.Read("core"))!["spaces"]![0]!["tabs"], saved["spaces"]![0]!["tabs"]));
        Assert.Equal(original.Read(fixture.Space.ToString()), authority.Checkpoint().Read(fixture.Space.ToString()));
        var invalid = JsonNode.Parse(SpaceCommand(session, "space.access", new() { ["value"] = "open" }))!;
        invalid["profileId"] = Guid.NewGuid().ToString();
        Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(Bytes(invalid)));
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
        authority.PrepareCommand(SpaceCommand(session, "space.deletion.begin", args.DeepClone().AsObject(), window: window)).Commit();
        Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(SpaceCommand(session, "space.deletion.begin", new() { ["operationID"] = Guid.NewGuid().ToString("D") }, second)));
        var command = authority.PrepareCommand(SpaceCommand(session, "space.remove", args.DeepClone().AsObject()));
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
        Assert.Throws<BrowserRuleException>(() => authority.PrepareCommand(SpaceCommand(projection, "space.deletion.begin", args.DeepClone().AsObject())));
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
        var command = authority.PrepareCommand(SpaceCommand(session, "space.deletion.begin", args.DeepClone().AsObject(), window: window));
        using (var cancelled = command.Reserve()) {
            Assert.Equal(1UL, authority.Revision);
            Assert.Null(JsonNode.Parse(authority.Checkpoint().Read("core"))!["spaceDeletions"]);
            Assert.Throws<BrowserRuleException>(() => authority.Commit(RenameDelta(session, "Racing write")));
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
        Assert.Throws<BrowserRuleException>(() => restarted.Commit(RenameDelta(restored, "Late page callback")));
        Assert.Throws<BrowserRuleException>(() => restarted.PrepareCommand(SpaceCommand(restored, "space.identity", new() { ["name"] = "Revived", ["symbol"] = "globe", ["accent"] = "teal" })));
        Assert.Throws<BrowserRuleException>(() => restarted.PrepareCommand(SpaceCommand(restored, "space.remove", new() { ["operationID"] = Guid.NewGuid().ToString() })));
        var completion = restarted.PrepareCommand(SpaceCommand(restored, "space.remove", args.DeepClone().AsObject()));
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
        var command = authority.PrepareCommand(SpaceCommand(session, "space.create", new() { ["template"] = template }));
        command.Commit();
        var projection = JsonNode.Parse(command.Output)!["session"]!;
        var added = projection["spaces"]![1]!;
        Assert.Equal("Private 2", added["name"]!.GetValue<string>());
        Assert.Equal("duckDuckGo", added["browsingPreferences"]!["selectedSearchProviderID"]!.GetValue<string>());
        Assert.Equal("never", added["browsingPreferences"]!["currentTabCleanupPolicy"]!.GetValue<string>());
        Assert.False(added["credentialPreferences"]!["syncsCrestPasswordsWithICloud"]!.GetValue<bool>());
        Assert.Null(projection["coreWorkspaceKind"]);
        var deletion = new JsonObject { ["operationID"] = Guid.NewGuid().ToString("D") };
        authority.PrepareCommand(SpaceCommand(projection, "space.deletion.begin", deletion)).Commit();
        var fresh = template.DeepClone();
        fresh["id"] = SwiftId(Guid.NewGuid()); fresh["profile"]!["id"] = Guid.NewGuid().ToString("D");
        var reset = authority.PrepareCommand(SpaceCommand(projection, "space.reset_private", new() { ["template"] = fresh }));
        reset.Commit();
        var cleared = JsonNode.Parse(reset.Output)!["session"]!;
        Assert.Single(cleared["spaces"]!.AsArray());
        Assert.Null(cleared["spaceDeletions"]);
        Assert.Equal("Private", cleared["spaces"]![0]!["name"]!.GetValue<string>());
        var borrowed = Borrow(authority, cleared);
        Assert.Throws<BrowserRuleException>(() => borrowed.PrepareCommand(SpaceCommand(session, "space.identity", new() { ["name"] = "Changed", ["symbol"] = "globe", ["accent"] = "teal" })));
    }

    [Fact]
    public void SpaceReorderingUsesOriginalOffsetsAndClampsTheInsertionPoint() {
        Assert.Equal(new[] { "b", "d", "a", "c" }, SpaceOrganizationPolicy.Move(new[] { "a", "b", "c", "d" }, [2, 0, 2, -1, 9], 4));
        Assert.Equal(new[] { "c", "a", "b" }, SpaceOrganizationPolicy.Move(new[] { "a", "b", "c" }, [2], int.MinValue));
    }
}
