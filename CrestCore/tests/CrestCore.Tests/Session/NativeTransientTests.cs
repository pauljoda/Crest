using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static JsonObject TransientRequest(JsonNode session, int destination = 0, bool empty = false) {
        var source = session["spaces"]![0]!; var target = session["spaces"]![destination]!;
        var tab = source["tabs"]![0]!.DeepClone(); tab["id"] = SwiftId(Guid.NewGuid());
        return new() {
            ["version"] = 1,
            ["operation"] = "transient.promote",
            ["spaceId"] = target["id"]!.DeepClone(),
            ["profileId"] = target["profile"]!["id"]!.DeepClone(),
            ["view"] = View(session),
            ["now"] = 800000100.0,
            ["arguments"] = new JsonObject {
                ["requestId"] = Guid.NewGuid().ToString(),
                ["sourceSpaceId"] = source["id"]!.DeepClone(),
                ["sourceProfileId"] = source["profile"]!["id"]!.DeepClone(),
                ["leaseSpaceId"] = source["id"]!.DeepClone(),
                ["leaseProfileId"] = source["profile"]!["id"]!.DeepClone(),
                ["sourceAccessible"] = true,
                ["destinationAccessible"] = true,
                ["supportsLiveAdoption"] = true,
                ["tab"] = empty ? null : tab
            }
        };
    }

    [Fact]
    public void TransientPromotionCommitsOnceAndCancelledStorageDoesNotConsumeTheRequest() {
        var session = SavedSession().Document["session"]!;
        var owner = new NativeSessionAuthority(Bytes(session)); var request = TransientRequest(session);
        var directEdit = request.DeepClone(); directEdit["operation"] = "tab.promote_transient";
        Assert.Equal("transient_requires_command", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(1, Bytes(directEdit))).Code);
        var command = owner.PrepareCommand(1, Bytes(request));
        var result = JsonNode.Parse(command.Output)!;
        Assert.True(result["adoptLivePage"]!.GetValue<bool>());
        Assert.Equal(2, result["space"]!["tabs"]!.AsArray().Count);
        var promoted = result["space"]!["tabs"]![1]!;
        Assert.Equal("current", promoted["placement"]!.GetValue<string>());
        Assert.Null(promoted["folderID"]); Assert.Null(promoted["savedURL"]);
        Assert.True(JsonNode.DeepEquals(promoted["iconAccent"], session["spaces"]![0]!["tabs"]![0]!["iconAccent"]));
        using (command.Reserve()) { }
        Assert.Equal(1UL, owner.Revision);
        using (var accepted = owner.PrepareCommand(1, Bytes(request)).Reserve()) accepted.Commit();
        Assert.Equal(2UL, owner.Revision);
        Assert.Equal("transient_already_completed", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(2, Bytes(request))).Code);
        request["operation"] = "transient.archive";
        Assert.Equal("transient_already_completed", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(2, Bytes(request))).Code);
        Assert.Empty(JsonNode.Parse(owner.Checkpoint(2).Read("core"))!["spaces"]![0]!["archivedTabs"]!.AsArray());
    }

    [Fact]
    public void TransientPromotionChecksOwnedProfilesAndAccessBeforePublishing() {
        var session = SavedSession().Document["session"]!;
        session["spaces"]!.AsArray().Add(SavedSession().Document["session"]!["spaces"]![0]!.DeepClone());
        var owner = new NativeSessionAuthority(Bytes(session)); var request = TransientRequest(session, 1);
        var args = request["arguments"]!;
        foreach (var key in new[] { "sourceAccessible", "destinationAccessible" }) {
            args[key] = false;
            Assert.Equal("transient_space_locked", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(1, Bytes(request))).Code);
            args[key] = true;
        }
        var profile = args["sourceProfileId"]!.DeepClone(); args["sourceProfileId"] = Guid.NewGuid().ToString();
        Assert.Equal("wrong_profile_identity", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(1, Bytes(request))).Code);
        args["sourceProfileId"] = profile;
        var sourceId = args["sourceSpaceId"]!.DeepClone(); args["sourceSpaceId"] = Guid.NewGuid().ToString();
        Assert.Equal("unknown_space", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(1, Bytes(request))).Code);
        args["sourceSpaceId"] = sourceId;
        args["leaseProfileId"] = Guid.NewGuid().ToString();
        Assert.Equal("wrong_transient_profile", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(1, Bytes(request))).Code);
        args["leaseProfileId"] = profile.DeepClone();
        var destinationProfile = request["profileId"]!.DeepClone(); request["profileId"] = Guid.NewGuid().ToString();
        Assert.Equal("wrong_profile_identity", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(1, Bytes(request))).Code);
        request["profileId"] = destinationProfile;
        Assert.Equal(1UL, owner.Revision);
        var command = owner.PrepareCommand(1, Bytes(request));
        Assert.False(JsonNode.Parse(command.Output)!["adoptLivePage"]!.GetValue<bool>());
        command.Commit();
        var after = JsonNode.Parse(owner.Checkpoint(2).Read("core"))!;
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0]!["tabs"], after["spaces"]![0]!["tabs"]));
        Assert.Equal(2, after["spaces"]![1]!["tabs"]!.AsArray().Count);
    }

    [Fact]
    public void TransientArchiveKeepsSelectionAndRejectsDuplicateOrRevokedCompletion() {
        var session = SavedSession().Document["session"]!;
        session["spaces"]!.AsArray().Add(SavedSession().Document["session"]!["spaces"]![0]!.DeepClone());
        var owner = new NativeSessionAuthority(Bytes(session)); var request = TransientRequest(session);
        request["operation"] = "transient.archive";
        request["arguments"]!["sourceAccessible"] = false; // A retained value may be archived after relocking.
        var command = owner.PrepareCommand(1, Bytes(request));
        var result = JsonNode.Parse(command.Output)!;
        Assert.True(LeavesSelection(result));
        Assert.Null(result["space"]!["selectedTabID"]);
        Assert.Equal("quickWindow", result["space"]!["archivedTabs"]![0]!["reason"]!.GetValue<string>());
        command.Commit();
        Assert.Equal("transient_already_completed", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(2, Bytes(request))).Code);
        var pendingRequest = TransientRequest(session); pendingRequest["operation"] = "transient.archive";
        var pending = owner.PrepareCommand(2, Bytes(pendingRequest));
        owner.PrepareCommand(2, SpaceCommand(session, "space.deletion.begin", new() { ["operationID"] = Guid.NewGuid().ToString() })).Commit();
        Assert.Throws<BrowserRuleException>(() => pending.Commit());
        Assert.Equal("space_deletion_in_progress", Assert.Throws<BrowserRuleException>(() => owner.PrepareCommand(3, Bytes(pendingRequest))).Code);
        Assert.Single(JsonNode.Parse(owner.Checkpoint(3).Read("core"))!["spaces"]![0]!["archivedTabs"]!.AsArray());
    }

    [Fact]
    public void EmptyTransientPromotionSelectsWithoutCreatingATab() {
        var session = SavedSession().Document["session"]!;
        session["spaces"]!.AsArray().Add(SavedSession().Document["session"]!["spaces"]![0]!.DeepClone());
        var owner = new NativeSessionAuthority(Bytes(session)); var request = TransientRequest(session, 1, empty: true);
        request["arguments"]!["leaseSpaceId"] = null; request["arguments"]!["leaseProfileId"] = null;
        var command = owner.PrepareCommand(1, Bytes(request)); var result = JsonNode.Parse(command.Output)!;
        Assert.Null(result["tabId"]);
        Assert.Equal(SpaceId(session["spaces"]![1]!), HintedSpace(result));
        Assert.False(result["adoptLivePage"]!.GetValue<bool>());
        Assert.True(JsonNode.DeepEquals(session["spaces"]![1]!["tabs"], result["space"]!["tabs"]));
        command.Commit();
        Assert.Equal(2UL, owner.Revision);
    }
}
