using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static readonly Guid Session = Guid.NewGuid();
    private static readonly Adapter[] Adapters = [Adapter("ui"), Adapter("engine"), Adapter("platform")];
    private static Adapter Adapter(string role) => Protocol.Descriptor(Descriptor(role));
    private static byte[] Descriptor(string role, string capabilityStatus = "supported") => Encoding.UTF8.GetBytes($$$$"""
        {"adapterId":"{{{{role}}}}","role":"{{{{role}}}}","implementationId":"fixture","implementationVersion":"1","protocolVersion":1,
        "capabilities":{"pages":{"status":"{{{{capabilityStatus}}}}","contractVersion":1,"scope":"test","limitations":[],"evidence":"contract suite"},
        "navigation":{"status":"supported","contractVersion":1,"scope":"test","limitations":[],"evidence":"contract suite"},
        "surfaces":{"status":"supported","contractVersion":1,"scope":"test","limitations":[],"evidence":"contract suite"}}}
        """);
    private static Envelope Message(string type, JsonObject body, string sender = "ui", Guid? cause = null, Guid? operation = null)
    {
        // Business fixtures must name commands that can actually enter through
        // the registered transport, including the correct provider role.
        Assert.Equal(sender, Protocol.Incoming[type]);
        return new(Session, Guid.NewGuid(), operation ?? Guid.NewGuid(), cause, sender, "core", 1,
            sender == "ui" ? "command" : "observation", type, Protocol.Parse(Encoding.UTF8.GetBytes(body.ToJsonString())));
    }
    private static JsonObject Selection(WindowId window, SpaceId space, TabId? tab = null) => new()
    { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString(), ["tabId"] = tab?.Value.ToString() };
    private static (BrowserKernel Core, WindowId Window, SpaceId Space) Kernel()
    {
        var core = new BrowserKernel(Adapters); var window = new WindowId(Guid.NewGuid());
        core.Process(Message("core.open_window", new() { ["windowId"] = window.Value.ToString() }));
        return (core, window, core.Workspace.Spaces[0].Id);
    }
    private static Outgoing Open(BrowserKernel core, WindowId window, SpaceId space)
    {
        var p = new JsonObject { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString(),
            ["url"] = "https://example.com", ["disposition"] = "foreground" };
        return core.Process(Message("core.open_tab", p)).Single(o => o.Type == "engine.create_page");
    }
    private static JsonObject Observation(Outgoing effect) => new()
    {
        ["spaceId"] = effect.Payload["spaceId"]!.GetValue<string>(), ["tabId"] = effect.Payload["tabId"]!.GetValue<string>(),
        ["pageId"] = effect.Payload["pageId"]!.GetValue<string>(), ["generation"] = "1"
    };
    [Fact]
    public void MalformedObservationCannotPartiallyMutatePageState()
    {
        var (core, window, space) = Kernel(); var create = Open(core, window, space);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var tab = core.Workspace.Space(space).Tabs.Single();
        var changed = Observation(create);
        changed["url"] = "https://example.org"; changed["title"] = "Changed";
        changed["isLoading"] = true; changed["canGoBack"] = true; changed["canGoForward"] = false;
        changed["committed"] = "not-a-boolean";
        Assert.Contains(core.Process(Message("engine.page_changed", changed, "engine")), o => o.Type == "core.operation_failed");
        Assert.Equal("https://example.com", tab.Url);
        Assert.False(tab.IsLoading);
        Assert.Empty(core.Workspace.Space(space).History);
    }
    [Fact]
    public void SupersededSurfaceAcknowledgmentsCannotChangeTheCurrentSelection()
    {
        var (core, window, space) = Kernel(); var create = Open(core, window, space);
        var attached = core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId))
            .Single(o => o.Type == "platform.assign_surface");
        var replacement = core.Process(Message("core.select_tab", Selection(window, space)))
            .Single(o => o.Type == "platform.assign_surface");
        JsonObject Ack(Outgoing effect) => new()
        {
            ["windowId"] = effect.Payload["windowId"]!.GetValue<string>(),
            ["leaseId"] = effect.Payload["leaseId"]!.GetValue<string>()
        };
        Assert.Empty(core.Process(Message("platform.surface_attached", Ack(attached), "platform", attached.Id, attached.CorrelationId)));
        Assert.Null(core.Workspace.Window(window).Selection(space));
        Assert.Contains(core.Process(Message("platform.surface_attached", Ack(replacement), "platform", Guid.NewGuid(), replacement.CorrelationId)),
            o => o.Type == "core.operation_failed");
        Assert.Empty(core.Process(Message("platform.surface_attached", Ack(replacement), "platform", replacement.Id, replacement.CorrelationId)));
    }
    [Fact]
    public void EngineOpenRequestUsesTheSourcePagesWindowAndRejectsStaleSources()
    {
        var (core, empty, space) = Kernel(); var owner = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(owner);
        var create = Open(core, owner, space);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var source = core.Workspace.Space(space).Tabs.Single();
        var request = Observation(create); request["url"] = "https://example.org";
        var effects = core.Process(Message("engine.open_requested", request, "engine"));
        var opened = Assert.Single(effects, o => o.Type == "engine.create_page");
        Assert.Equal(owner.Value.ToString(), opened.Payload["windowId"]!.GetValue<string>());
        Assert.Null(core.Workspace.Window(empty).Selection(space));
        Assert.NotEqual(source.Id, core.Workspace.Window(owner).Selection(space));
        Assert.Contains(core.Process(Message("engine.open_requested", request, "engine")), o => o.Type == "core.operation_failed");
        Assert.Equal(2, core.Workspace.Space(space).Tabs.Count);
    }
    [Fact]
    public void ClosingDuringCreationDisposesLatePageWithoutNavigating()
    {
        var (core, window, space) = Kernel(); var create = Open(core, window, space);
        var tab = core.Workspace.Space(space).Tabs.Single();
        core.Process(Message("core.close_tab", Selection(window, space, tab.Id)));
        var output = core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        Assert.DoesNotContain(output, o => o.Type == "engine.navigate");
        var close = Assert.Single(output, o => o.Type == "engine.close_page");
        core.Process(Message("engine.page_closed", Observation(close), "engine", close.Id, close.CorrelationId));
        Assert.Empty(core.Workspace.Space(space).Tabs);
    }
    [Fact]
    public void CanceledNativeClosePreservesTabAndSelection()
    {
        var (core, window, space) = Kernel(); var create = Open(core, window, space);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var tab = core.Workspace.Space(space).Tabs.Single();
        var close = core.Process(Message("core.close_tab", Selection(window, space, tab.Id))).Single(o => o.Type == "engine.close_page");
        core.Process(Message("engine.close_canceled", Observation(close), "engine", close.Id, close.CorrelationId));
        Assert.Equal(TabPhase.Ready, tab.Phase); Assert.Equal(tab.Id, core.Workspace.Window(window).Selection(space));
    }
    [Fact]
    public void EmptyWindowSelectionSurvivesAnotherWindowsOpenAndClose()
    {
        var (core, window, space) = Kernel(); var empty = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(empty);
        var create = Open(core, window, space); var tab = core.Workspace.Space(space).Tabs.Single();
        Assert.Null(core.Workspace.Window(empty).Selection(space));
        core.Workspace.Close(space, tab.Id);
        Assert.Null(core.Workspace.Window(empty).Selection(space));
        Assert.True(core.Workspace.Window(empty).Selections.ContainsKey(space));
    }
    [Fact]
    public void SettingsTabDoesNotCreateAnEnginePage()
    {
        var (core, window, space) = Kernel();
        var p = new JsonObject { ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString(), ["disposition"] = "foreground" };
        Assert.DoesNotContain(core.Process(Message("core.open_settings", p)), o => o.Recipient == "engine");
        Assert.Null(core.Workspace.Space(space).Tabs.Single().PageId);
    }
    [Fact]
    public void WrongGenerationCannotBindPage()
    {
        var (core, window, space) = Kernel(); var create = Open(core, window, space); var p = Observation(create); p["generation"] = "2";
        var output = core.Process(Message("engine.page_created", p, "engine", create.Id, create.CorrelationId));
        Assert.Contains(output, o => o.Type == "core.operation_failed");
        Assert.Equal(TabPhase.Creating, core.Workspace.Space(space).Tabs.Single().Phase);
    }
    [Fact]
    public void ForeignSpaceSelectionAndPrivilegedUrlsFailWithoutMutation()
    {
        var (core, window, space) = Kernel(); Open(core, window, space);
        var tab = core.Workspace.Space(space).Tabs.Single(); var other = core.Workspace.Spaces[1];
        Assert.Throws<BrowserRuleException>(() => core.Workspace.Select(window, other.Id, tab.Id));
        Assert.Throws<BrowserRuleException>(() => core.Workspace.Open(window, space, "javascript:alert(1)", TabKind.Web, true));
        Assert.Single(core.Workspace.Space(space).Tabs);
    }
    [Fact]
    public void CloseFallbackDoesNotClaimAnotherWindowsNativePage()
    {
        var (core, first, space) = Kernel(); var second = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(second);
        var retained = core.Workspace.Open(first, space, "https://example.com", TabKind.Web, true);
        var closed = core.Workspace.Open(second, space, "https://example.org", TabKind.Web, true);
        core.Workspace.Close(space, closed.Id);
        Assert.Equal(retained.Id, core.Workspace.Window(first).Selection(space));
        Assert.Null(core.Workspace.Window(second).Selection(space));
        Assert.Single(core.Workspace.Space(space).Archive);
    }
    [Fact]
    public void NativeViewSelectionCannotBeClaimedByTwoWindows()
    {
        var (core, window, space) = Kernel(); Open(core, window, space);
        var tab = core.Workspace.Space(space).Tabs.Single(); var second = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(second);
        Assert.Throws<BrowserRuleException>(() => core.Workspace.Select(second, space, tab.Id));
        Assert.Null(core.Workspace.Window(second).Selection(space));
        Assert.Equal(tab.Id, core.Workspace.Window(window).Selection(space));
        core.Workspace.CloseWindow(window);
        core.Workspace.Select(second, space, tab.Id);
        Assert.Equal(tab.Id, core.Workspace.Window(second).Selection(space));
    }
    [Fact]
    public void QuiescingCreationCompletesWithoutNavigatingOrAttaching()
    {
        var (core, window, space) = Kernel(); var create = Open(core, window, space);
        core.BeginShutdown();
        var output = core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        Assert.DoesNotContain(output, o => o.Kind == "effect");
        Assert.Equal(0, core.PendingEffectCount);
    }
    [Fact]
    public void WrongEffectCannotCloseAnotherTab()
    {
        var (core, window, space) = Kernel(); var first = Open(core, window, space); var second = Open(core, window, space);
        core.Process(Message("engine.page_created", Observation(first), "engine", first.Id, first.CorrelationId));
        core.Process(Message("engine.page_created", Observation(second), "engine", second.Id, second.CorrelationId));
        var tab = core.Workspace.Space(space).Tabs[0];
        var close = core.Process(Message("core.close_tab", Selection(window, space, tab.Id))).Single(o => o.Type == "engine.close_page");
        var wrong = Observation(second);
        Assert.Contains(core.Process(Message("engine.page_closed", wrong, "engine", close.Id, close.CorrelationId)), o => o.Type == "core.operation_failed");
        Assert.Equal(2, core.Workspace.Space(space).Tabs.Count);
        Assert.Equal(1, core.PendingEffectCount);
    }
    [Theory]
    [InlineData("{\"a\":1,\"a\":2}")]
    [InlineData("{\"nested\":{\"a\":1,\"a\":2}}")]
    public void DuplicateMembersAreRejected(string json) => Assert.Throws<ProtocolException>(() => Protocol.Parse(Encoding.UTF8.GetBytes(json)));
    [Fact]
    public void MalformedUtf8IsRejected() => Assert.Throws<DecoderFallbackException>(() => Protocol.Parse([0x22, 0xff, 0x22]));
    [Fact]
    public void UnverifiedRequiredCapabilityCannotStart()
    {
        var core = Runtime();
        Assert.Equal(0, core.Register(Descriptor("ui"))); Assert.Equal(0, core.Register(Descriptor("platform")));
        Assert.Equal(0, core.Register(Descriptor("engine", "unverified")));
        Assert.Equal(CoreStatus.InvalidState, core.Start()); Assert.True(core.CanDestroy);
    }
    private static CoreRuntime Runtime() => new(new(Session, 8192, 4096));
    private static byte[] Input(Guid id, ulong sequence = 1, string sender = "ui", Guid? session = null)
    {
        var node = JsonNode.Parse(Protocol.Encode(session ?? Session, id, id, null, "core", sequence, "command", "core.snapshot", new()))!;
        node["sender"] = sender; return Encoding.UTF8.GetBytes(node.ToJsonString());
    }
    [Fact]
    public void TransportChecksRoleSessionSequenceAndDuplicateIdentity()
    {
        var core = Runtime(); foreach (var role in new[] { "ui", "engine", "platform" }) core.Register(Descriptor(role));
        Assert.Equal(0, core.Start()); Assert.Equal(CoreStatus.InvalidState, core.Register(Descriptor("services")));
        var id = Guid.NewGuid(); var input = Input(id);
        Assert.Equal(CoreStatus.InvalidMessage, core.Post(Input(id, sender: "engine")));
        Assert.Equal(CoreStatus.InvalidMessage, core.Post(Input(id, session: Guid.NewGuid())));
        Assert.Equal(CoreStatus.InvalidMessage, core.Post(Input(id, sequence: 2)));
        Assert.Equal(0, core.Post(input)); Assert.Equal(0, core.Post(input));
        Assert.Equal(CoreStatus.InvalidMessage, core.Post(Input(id, sequence: 2)));
        Stop(core);
    }
    [Fact]
    public void OutputSizeProbeDoesNotConsumeAndShutdownRequiresNativeAcknowledgment()
    {
        var core = Runtime(); foreach (var role in new[] { "ui", "engine", "platform" }) core.Register(Descriptor(role));
        core.Start(); core.Post(Input(Guid.NewGuid()));
        Assert.Equal(0, core.WaitOutput(2000));
        Assert.Equal(CoreStatus.BufferTooSmall, core.Read([], out int length)); Assert.True(length > 0);
        Assert.Equal(CoreStatus.BufferTooSmall, core.Read(new byte[length - 1], out int again)); Assert.Equal(length, again);
        Assert.Equal(0, core.Read(new byte[length], out _));
        core.BeginShutdown(); Assert.Equal(CoreStatus.Timeout, core.WaitStopped(0));
        Stop(core);
    }
    [Fact]
    public void OutputLimitEndsSessionWithAContiguousFailureMessage()
    {
        var core = new CoreRuntime(new(Session, 4096, 512));
        foreach (var role in new[] { "ui", "engine", "platform" }) core.Register(Descriptor(role));
        Assert.Equal(CoreStatus.Ok, core.Start());
        Assert.Equal(CoreStatus.Ok, core.Post(Input(Guid.NewGuid())));
        Assert.Equal(CoreStatus.Ok, core.WaitOutput(2000));
        core.Read([], out int length); var bytes = new byte[length];
        Assert.Equal(CoreStatus.Ok, core.Read(bytes, out _));
        var message = Protocol.Decode(bytes);
        Assert.Equal(1UL, message.Sequence);
        Assert.Equal("session_failed", message.Payload.GetProperty("code").GetString());
        Assert.Equal(CoreStatus.Ok, core.WaitStopped(2000));
        Assert.True(core.CanDestroy);
    }
    [Fact]
    public void SaturationRejectsBeforeAcceptanceAndTheSameMessageCanBeRetried()
    {
        var core = Runtime(); foreach (var role in new[] { "ui", "engine", "platform" }) core.Register(Descriptor(role));
        core.Start();
        byte[] rejected = [];
        for (ulong sequence = 1; sequence <= 1000; sequence++)
        {
            var bytes = Input(Guid.NewGuid(), sequence);
            int status = core.Post(bytes);
            if (status == CoreStatus.Busy) { rejected = bytes; break; }
            Assert.Equal(CoreStatus.Ok, status);
        }
        Assert.NotEmpty(rejected);
        bool accepted = false;
        for (int attempt = 0; attempt < 100; attempt++)
        {
            Assert.Equal(CoreStatus.Ok, core.WaitOutput(2000));
            core.Read([], out int length); core.Read(new byte[length], out _);
            int status = core.Post(rejected);
            if (status == CoreStatus.Ok) { accepted = true; break; }
            Assert.Equal(CoreStatus.Busy, status);
        }
        Assert.True(accepted);
        Assert.Equal(CoreStatus.Ok, core.Post(rejected));
        Stop(core);
    }
    private static void Stop(CoreRuntime core)
    {
        core.BeginShutdown();
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < deadline)
        {
            int status = core.WaitOutput(100);
            if (status == CoreStatus.Stopped) { Assert.Equal(0, core.WaitStopped(1000)); return; }
            if (status != CoreStatus.Ok) continue;
            core.Read([], out int count); var bytes = new byte[count]; core.Read(bytes, out _);
            var e = Protocol.Decode(bytes);
            if (e.Type == "engine.dispose_all")
            {
                var node = JsonNode.Parse(Protocol.Encode(Session, Guid.NewGuid(), e.CorrelationId, e.Id, "core", 1, "observation", "engine.stopped", new()))!;
                node["sender"] = "engine"; Assert.Equal(0, core.Post(Encoding.UTF8.GetBytes(node.ToJsonString())));
            }
        }
        Assert.Fail("Core did not finish acknowledged shutdown");
    }
}
