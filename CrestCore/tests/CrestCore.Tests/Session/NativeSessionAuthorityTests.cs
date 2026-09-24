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
}
