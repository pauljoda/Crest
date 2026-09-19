using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static Adapter[] AuthenticationAdapters => Adapters.Select(a => a.Role != "platform" ? a : a with
    { Capabilities = new Dictionary<string, Capability>(a.Capabilities) { ["device-authentication"] = new("supported", 1, "test", [], "contract suite") } }).ToArray();
    private static JsonObject AuthenticationReply(Outgoing request) => new()
    {
        ["spaceId"] = request.Payload["spaceId"]!.DeepClone(), ["profileId"] = request.Payload["profileId"]!.DeepClone(),
        ["generation"] = request.Payload["generation"]!.DeepClone(), ["outcome"] = "succeeded"
    };
    [Fact]
    public void LockHidesTabsAndSurfacesAndOnlyMatchingAuthenticationCanUnlockThem()
    {
        var core = new BrowserKernel(AuthenticationAdapters); var window = new WindowId(Guid.NewGuid());
        core.Process(Message("core.open_window", new() { ["windowId"] = window.Value.ToString() }));
        var space = core.Workspace.Spaces[0]; var create = Open(core, window, space.Id);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var tab = Assert.Single(space.Tabs);
        var target = new JsonObject { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Id.Value.ToString() };
        var policy = (JsonObject)target.DeepClone(); policy["requiresAuthentication"] = true;
        var locked = core.Process(Message("core.set_space_access", policy));
        Assert.True(space.IsLocked);
        Assert.Empty(locked.Single(e => e.Type == "platform.assign_surface").Payload["panes"]!.AsArray());
        var snapshot = locked.Single(e => e.Type == "ui.snapshot").Payload;
        Assert.Empty(snapshot["spaces"]![0]!["tabs"]!.AsArray()); Assert.Null(snapshot["windows"]![0]!["tabId"]);
        Assert.Contains(core.Process(Message("core.navigate_input", new() { ["windowId"] = window.Value.ToString(),
            ["spaceId"] = space.Id.Value.ToString(), ["input"] = "example.org" })), e => e.Payload["code"]?.GetValue<string>() == "space_locked");
        var request = core.Process(Message("core.unlock_space", target)).Single(e => e.Type == "platform.authenticate_space");
        var forged = AuthenticationReply(request); forged["profileId"] = Guid.NewGuid().ToString();
        core.Process(Message("platform.authentication_completed", forged, "platform", request.Id, request.CorrelationId));
        Assert.True(space.IsLocked);
        var restored = core.Process(Message("platform.authentication_completed", AuthenticationReply(request), "platform", request.Id, request.CorrelationId));
        Assert.False(space.IsLocked); Assert.Equal(tab.Id, core.Workspace.Window(window).Selection(space.Id));
        Assert.Single(restored.Single(e => e.Type == "platform.assign_surface").Payload["pages"]!.AsArray());
        Assert.True(BrowserWorkspace.Restore(core.Workspace.Capture(), new SystemIdSource(), new SystemClock()).Spaces[0].IsLocked);
    }
    [Fact]
    public void LockCancelsAuthenticationAndLateSuccessCannotReopenTheSpace()
    {
        var core = new BrowserKernel(AuthenticationAdapters); var window = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(window); var space = core.Workspace.Spaces[0]; space.SetAccessPolicy(true);
        var target = new JsonObject { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Id.Value.ToString() };
        var request = core.Process(Message("core.unlock_space", target)).Single(e => e.Type == "platform.authenticate_space");
        core.Process(Message("core.lock_all", new())); // The native system prompt makes a scene inactive.
        var canceled = core.Process(Message("core.lock_space", target));
        Assert.Contains(canceled, e => e.Type == "platform.cancel_authentication");
        Assert.Empty(core.Process(Message("platform.authentication_completed", AuthenticationReply(request), "platform", request.Id, request.CorrelationId)));
        Assert.True(space.IsLocked);
        var second = core.Process(Message("core.unlock_space", target)).Single(e => e.Type == "platform.authenticate_space");
        core.BeginShutdown();
        Assert.Empty(core.Process(Message("platform.authentication_completed", AuthenticationReply(second), "platform", second.Id, second.CorrelationId)));
        Assert.True(space.IsLocked);
    }
    [Fact]
    public void NativeLifecycleStillDrainsAfterLockWithoutPublishingProtectedMetadata()
    {
        var core = new BrowserKernel(AuthenticationAdapters); var window = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(window); var space = core.Workspace.Spaces[0]; var create = Open(core, window, space.Id);
        var tab = Assert.Single(space.Tabs);
        core.Process(Message("core.close_tab", Selection(window, space.Id, tab.Id)));
        core.Process(Message("core.set_space_access", new() { ["windowId"] = window.Value.ToString(),
            ["spaceId"] = space.Id.Value.ToString(), ["requiresAuthentication"] = true }));
        var closing = core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var close = closing.Single(e => e.Type == "engine.close_page");
        core.Process(Message("engine.page_closed", Observation(close), "engine", close.Id, close.CorrelationId));
        Assert.Empty(space.Tabs); Assert.Equal(0, core.PendingEffectCount); Assert.True(space.IsLocked);
    }
    [Fact]
    public void RestoredProtectedSpaceCanAuthenticateAndCancellationIsNotAnInvalidPayload()
    {
        var fixture = SavedSession();
        fixture.Document["session"]!["spaces"]![0]!["accessPolicy"] = "deviceOwnerAuthentication";
        var core = new BrowserSessionKernel(AuthenticationAdapters, initialState: fixture.Document);
        core.Process(Message("core.open_window", new() { ["windowId"] = fixture.Window.Value.ToString() }));
        var target = new JsonObject { ["windowId"] = fixture.Window.Value.ToString(), ["spaceId"] = fixture.Space.Value.ToString() };
        var request = core.Process(Message("core.unlock_space", target)).Single(e => e.Type == "platform.authenticate_space");
        var canceled = AuthenticationReply(request); canceled["outcome"] = "canceled";
        var result = core.Process(Message("platform.authentication_completed", canceled, "platform", request.Id, request.CorrelationId));
        Assert.Contains(result, e => e.Payload["code"]?.GetValue<string>() == "authentication_canceled");
        Assert.True(core.Workspace.Space(fixture.Space).IsLocked);
        request = core.Process(Message("core.unlock_space", target)).Single(e => e.Type == "platform.authenticate_space");
        core.Process(Message("platform.authentication_completed", AuthenticationReply(request), "platform", request.Id, request.CorrelationId));
        Assert.False(core.Workspace.Space(fixture.Space).IsLocked);
    }

}
