using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static Adapter[] ContentBlockingAdapters => WorkspaceAdapters.Select(a => a.Role != "engine" ? a : a with
    { Capabilities = new Dictionary<string, Capability>(a.Capabilities) { ["content-blocking"] = new("supported", 1, "test", [], "contract suite") } }).ToArray();
    private static JsonObject PolicyTarget(WindowId window, SpaceId space, string? policy = null)
    {
        var body = new JsonObject { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString() };
        if (policy is not null) body["policy"] = policy;
        return body;
    }
    private static JsonObject PolicyReply(Outgoing effect) => new()
    { ["spaceId"] = effect.Payload["spaceId"]!.DeepClone(), ["profileId"] = effect.Payload["profileId"]!.DeepClone() };

    [Fact]
    public void ContentBlockingCoalescesNativeWorkAndRequiresMatchingCompletion()
    {
        var core = new BrowserKernel(ContentBlockingAdapters); var window = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(window); var space = core.Workspace.Spaces[0];
        var first = core.Process(Message("core.set_content_blocking", PolicyTarget(window, space.Id, "off")))
            .Single(e => e.Type == "engine.apply_content_blocking");
        Assert.Equal(1, core.PendingEffectCount);
        Assert.DoesNotContain(core.Process(Message("core.set_content_blocking", PolicyTarget(window, space.Id, "balanced"))),
            e => e.Type == "engine.apply_content_blocking");
        var forged = PolicyReply(first); forged["profileId"] = Guid.NewGuid().ToString();
        Assert.Contains(core.Process(Message("engine.content_blocking_applied", forged, "engine", first.Id, first.CorrelationId)),
            e => e.Payload["code"]?.GetValue<string>() == "unknown_content_blocking_effect");
        Assert.Equal(1, core.PendingEffectCount);
        var next = core.Process(Message("engine.content_blocking_applied", PolicyReply(first), "engine", first.Id, first.CorrelationId))
            .Single(e => e.Type == "engine.apply_content_blocking");
        Assert.Equal("balanced", next.Payload["policy"]!.GetValue<string>());
        var failed = core.Process(Message("engine.content_blocking_failed", PolicyReply(next), "engine", next.Id, next.CorrelationId));
        Assert.Equal(0, core.PendingEffectCount);
        Assert.Equal(ContentBlockingPolicy.Balanced, space.ContentBlocking);
        Assert.Equal("content_blocking_failed", failed.Single(e => e.Type == "ui.snapshot").Payload["spaces"]![0]!["contentBlockingFailure"]!.GetValue<string>());
        var retry = core.Process(Message("core.retry_content_blocking", PolicyTarget(window, space.Id)))
            .Single(e => e.Type == "engine.apply_content_blocking");
        Assert.DoesNotContain(core.Process(Message("engine.content_blocking_applied", PolicyReply(retry), "engine", retry.Id, retry.CorrelationId)),
            e => e.Type == "engine.apply_content_blocking");
        Assert.Equal(0, core.PendingEffectCount);
    }
    [Fact]
    public void BorrowedWindowChangesCanonicalPolicyAndNewPagesCarryIt()
    {
        var core = new BrowserSessionKernel(ContentBlockingAdapters); var window = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(window); var source = core.Workspace.Spaces[0];
        var (borrowed, borrowedWindow, _) = CreateWorkspace(core, core.Workspace, "borrowed");
        var effect = core.Process(Message("core.set_content_blocking", PolicyTarget(borrowedWindow, source.Id, "off")))
            .Single(e => e.Type == "engine.apply_content_blocking");
        Assert.Equal(core.Workspace.Id.Value.ToString(), effect.Payload["workspaceId"]!.GetValue<string>());
        Assert.Equal(ContentBlockingPolicy.Off, source.ContentBlocking);
        Assert.Equal(ContentBlockingPolicy.Off, borrowed.Space(source.Id).ContentBlocking);
        var reply = PolicyReply(effect); reply["workspaceId"] = effect.Payload["workspaceId"]!.DeepClone();
        core.Process(Message("engine.content_blocking_applied", reply, "engine", effect.Id, effect.CorrelationId));
        var body = PolicyTarget(borrowedWindow, source.Id); body["url"] = "https://example.com"; body["disposition"] = "foreground";
        var page = core.Process(Message("core.open_tab", body)).Single(e => e.Type == "engine.create_page");
        Assert.Equal("off", page.Payload["contentBlockingPolicy"]!.GetValue<string>());
        var legacy = new LegacySessionDocument().Write(core.Workspace.Capture());
        Assert.Equal(ContentBlockingPolicy.Off, new LegacySessionDocument(legacy).Read(new SystemIdSource()).Spaces[0].ContentBlocking);
    }
    [Fact]
    public void UnsupportedEngineAndLockedSpaceCannotChangeContentBlocking()
    {
        var core = new BrowserKernel(Adapters); var window = new WindowId(Guid.NewGuid()); core.Workspace.AddWindow(window);
        var space = core.Workspace.Spaces[0];
        Assert.Contains(core.Process(Message("core.set_content_blocking", PolicyTarget(window, space.Id, "off"))),
            e => e.Payload["code"]?.GetValue<string>() == "capability_unavailable");
        Assert.Equal(ContentBlockingPolicy.Balanced, space.ContentBlocking);
        var supported = new BrowserKernel(ContentBlockingAdapters); supported.Workspace.AddWindow(window);
        var locked = supported.Workspace.Spaces[0]; locked.SetAccessPolicy(true);
        Assert.Contains(supported.Process(Message("core.set_content_blocking", PolicyTarget(window, locked.Id, "off"))),
            e => e.Payload["code"]?.GetValue<string>() == "space_locked");
        Assert.Equal(ContentBlockingPolicy.Balanced, locked.ContentBlocking);
    }
}
