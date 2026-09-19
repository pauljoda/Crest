using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static Adapter[] DeletionAdapters => [.. WorkspaceAdapters.Select(a => a.Role != "engine" ? a : a with
        { Capabilities = new Dictionary<string, Capability>(a.Capabilities) { ["profile-deletion"] = new("supported", 1, "test", [], "contract suite") } }),
        Adapter("services") with { Capabilities = new Dictionary<string, Capability>
        {
            ["session-storage"] = new("supported", 1, "test", [], "contract suite"),
            ["space-data-deletion"] = new("supported", 1, "test", [], "contract suite")
        } }];
    private static IReadOnlyList<Outgoing> AckSave(BrowserSessionKernel core, Outgoing effect, bool success = true) =>
        core.Process(Message(success ? "services.session_saved" : "services.save_failed",
            new() { ["revision"] = effect.Payload["revision"]!.DeepClone() }, "services", effect.Id, effect.CorrelationId));
    private static IReadOnlyList<Outgoing> AckCleanup(BrowserSessionKernel core, Outgoing effect, bool success = true)
    {
        string type = effect.Type == "engine.delete_profile" ? success ? "engine.profile_deleted" : "engine.profile_deletion_failed"
            : success ? "services.space_data_deleted" : "services.space_data_deletion_failed";
        var body = new JsonObject();
        foreach (var key in new[] { "spaceId", "profileId", "workspaceId" }) body[key] = effect.Payload[key]!.DeepClone();
        return core.Process(Message(type, body, effect.Recipient, effect.Id, effect.CorrelationId));
    }
    private static List<Outgoing> AckSurfaces(BrowserSessionKernel core, IEnumerable<Outgoing> output)
    {
        var result = output.ToList();
        foreach (var effect in result.Where(e => e.Type == "platform.assign_surface").ToArray())
            result.AddRange(core.Process(Message("platform.surface_attached", new()
            {
                ["windowId"] = effect.Payload["windowId"]!.DeepClone(), ["leaseId"] = effect.Payload["leaseId"]!.DeepClone()
            }, "platform", effect.Id, effect.CorrelationId)));
        return result;
    }
    private static (BrowserSessionKernel Core, WindowId Window, SpaceId Space) DeletionKernel(bool persistent = true, JsonObject? state = null)
    {
        var core = new BrowserSessionKernel(DeletionAdapters, initialState: state, persistSession: persistent);
        var window = new WindowId(Guid.NewGuid());
        var opened = core.Process(Message("core.open_window", new() { ["windowId"] = window.Value.ToString() }));
        foreach (var save in opened.Where(e => e.Type == "services.save_session")) AckSave(core, save);
        return (core, window, core.Workspace.Spaces[0].Id);
    }
    private static JsonObject DeletionTarget(WindowId window, SpaceId space) => new()
    { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString() };

    [Fact]
    public void DeletionWaitsForDurableIntentBorrowerReleaseAndSurfaceDetach()
    {
        var (core, window, space) = DeletionKernel();
        var (borrowed, _, _) = CreateWorkspace(core, core.Workspace, "borrowed");
        var requested = core.Process(Message("core.delete_space", DeletionTarget(window, space)));
        Assert.True(core.Workspace.Space(space).IsDeleting);
        var redacted = requested.Single(e => e.Type == "ui.snapshot" && e.Payload["workspaceId"]!.GetValue<string>() == borrowed.Id.Value.ToString());
        Assert.True(redacted.Payload["workspaceClosing"]!.GetValue<bool>());
        Assert.Empty(redacted.Payload["spaces"]![0]!["tabs"]!.AsArray());
        Assert.NotEqual(space, core.Workspace.Window(window).SpaceId);
        Assert.DoesNotContain(requested, e => e.Type is "engine.delete_profile" or "engine.release_workspace");
        var save = requested.Single(e => e.Type == "services.save_session");
        Assert.Single(save.Payload["state"]!["spaceDeletions"]!.AsArray());
        var durable = AckSave(core, save);
        Assert.DoesNotContain(durable, e => e.Type == "engine.release_workspace");
        var detached = AckSurfaces(core, requested);
        var release = detached.Single(e => e.Type == "engine.release_workspace");
        Assert.Equal(borrowed.Id.Value.ToString(), release.Payload["workspaceId"]!.GetValue<string>());
        Assert.DoesNotContain(detached, e => e.Type == "engine.delete_profile");
        var released = core.Process(Message("engine.workspace_released", new()
            { ["workspaceId"] = borrowed.Id.Value.ToString() }, "engine", release.Id, release.CorrelationId));
        var cleanup = released.Single(e => e.Type == "engine.delete_profile");
        var secrets = AckCleanup(core, cleanup).Single(e => e.Type == "services.delete_space_data");
        var completed = AckCleanup(core, secrets);
        Assert.DoesNotContain(core.Workspace.Spaces, s => s.Id == space);
        Assert.True(core.Workspace.SpaceDeletions.Single().Completed);
        Assert.Single(completed, e => e.Type == "services.save_session");
    }
    [Fact]
    public void FailedIntentSaveCannotDisposePagesOrBorrowedWorkspacesAndRetryResumes()
    {
        var (core, window, space) = DeletionKernel();
        CreateWorkspace(core, core.Workspace, "borrowed");
        var requested = AckSurfaces(core, core.Process(Message("core.delete_space", DeletionTarget(window, space))));
        var failed = AckSave(core, requested.Single(e => e.Type == "services.save_session"), false);
        Assert.DoesNotContain(failed, e => e.Recipient == "engine");
        Assert.True(core.SaveFailed);
        // A blocked cleanup is durable retry state, not an in-flight native
        // effect. Otherwise shutdown can never report its failed save.
        Assert.Equal(0, core.PendingEffectCount);
        Assert.Contains(core.Process(Message("core.new_tab", DeletionTarget(window, space))),
            e => e.Payload["code"]?.GetValue<string>() == "space_deleting");
        var retry = AckSurfaces(core, core.Process(Message("core.retry_space_deletion", DeletionTarget(window, space))));
        var persisted = AckSave(core, retry.Single(e => e.Type == "services.save_session"));
        Assert.Single(persisted, e => e.Type == "engine.release_workspace");
    }
    [Fact]
    public void DeletionRestartsFromPersistedIntentAndTombstonePreventsResurrection()
    {
        var (core, window, space) = DeletionKernel();
        var requested = core.Process(Message("core.delete_space", DeletionTarget(window, space)));
        var checkpoint = requested.Single(e => e.Type == "services.save_session").Payload["state"]!.AsObject();
        var restored = new BrowserSessionKernel(DeletionAdapters, initialState: checkpoint, persistSession: true);
        var resumed = restored.Process(Message("core.snapshot", new()));
        var profile = resumed.Single(e => e.Type == "engine.delete_profile");
        Assert.True(restored.Workspace.Space(space).IsDeleting);
        var services = AckCleanup(restored, profile).Single(e => e.Type == "services.delete_space_data");
        var saved = AckCleanup(restored, services).Single(e => e.Type == "services.save_session").Payload["state"]!.AsObject();
        // A stale incoming record cannot defeat a completed deletion marker.
        saved["session"]!["spaces"]!.AsArray().Add(checkpoint["session"]!["spaces"]!.AsArray()[0]!.DeepClone());
        var again = new BrowserSessionKernel(DeletionAdapters, initialState: saved, persistSession: true);
        Assert.DoesNotContain(again.Workspace.Spaces, s => s.Id == space);
        Assert.True(again.Workspace.SpaceDeletions.Single().Completed);
    }
    [Fact]
    public void ProviderFailureRetainsPendingDeletionAndRejectsForgedOrDuplicateAcknowledgments()
    {
        var (core, window, space) = DeletionKernel(false);
        var requested = AckSurfaces(core, core.Process(Message("core.delete_space", DeletionTarget(window, space))));
        var cleanup = requested.Single(e => e.Type == "engine.delete_profile");
        var wrong = (JsonObject)cleanup.Payload.DeepClone(); wrong.Remove("profileMode"); wrong.Remove("privateSourceProfileId");
        wrong["profileId"] = Guid.NewGuid().ToString();
        Assert.Contains(core.Process(Message("engine.profile_deleted", wrong, "engine", cleanup.Id, cleanup.CorrelationId)),
            e => e.Payload["code"]?.GetValue<string>() == "unknown_deletion_effect");
        var failure = AckCleanup(core, cleanup, false);
        Assert.True(core.Workspace.Space(space).IsDeleting);
        Assert.Contains(failure, e => e.Payload["code"]?.GetValue<string>() == "profile_cleanup_failed");
        Assert.DoesNotContain(core.Process(Message("core.snapshot", new())), e => e.Type == "engine.delete_profile");
        var retry = AckSurfaces(core, core.Process(Message("core.retry_space_deletion", DeletionTarget(window, space))));
        var next = retry.Single(e => e.Type == "engine.delete_profile");
        Assert.Contains(AckCleanup(core, cleanup), e => e.Payload["code"]?.GetValue<string>() == "unknown_deletion_effect");
        var secrets = AckCleanup(core, next).Single(e => e.Type == "services.delete_space_data");
        AckCleanup(core, secrets);
        Assert.True(core.Workspace.SpaceDeletions.Single().Completed);
    }
    [Fact]
    public void BorrowedProfileAndLastSurvivingSpaceCannotBeDeleted()
    {
        var (core, window, space) = DeletionKernel(false);
        var (_, borrowedWindow, _) = CreateWorkspace(core, core.Workspace, "borrowed");
        var rejected = core.Process(Message("core.delete_space", DeletionTarget(borrowedWindow, space)));
        Assert.Contains(rejected, e => e.Payload["code"]?.GetValue<string>() == "borrowed_workspace_fixed_profile");
        Assert.Empty(core.Workspace.SpaceDeletions);
        core.Process(Message("core.delete_space", DeletionTarget(window, space)));
        var last = core.Workspace.Window(window).SpaceId;
        Assert.Contains(core.Process(Message("core.delete_space", DeletionTarget(window, last))),
            e => e.Payload["code"]?.GetValue<string>() == "cannot_delete_last_space");
        Assert.False(core.Workspace.Space(last).IsDeleting);
    }
}
