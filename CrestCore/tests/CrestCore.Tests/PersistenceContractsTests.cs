using System.Text.Json.Nodes;
using System.Text;
using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static JsonObject SwiftId(Guid value) => new() { ["rawValue"] = value.ToString().ToUpperInvariant() };
    private static (JsonObject Document, SpaceId Space, TabId Tab, WindowId Window) SavedSession(bool empty = false)
    {
        var space = new SpaceId(Guid.NewGuid()); var tab = new TabId(Guid.NewGuid()); var window = new WindowId(Guid.NewGuid());
        var folder = Guid.NewGuid();
        JsonObject savedTab = new()
        {
            ["id"] = SwiftId(tab.Value), ["title"] = "Observed page", ["url"] = "https://example.com/article#one",
            ["placement"] = "saved", ["folderID"] = SwiftId(folder), ["savedURL"] = "https://example.com/",
            ["symbol"] = "crest.emoji:🌊", ["customTitle"] = "My reading", ["lastActivatedAt"] = 800000000.25,
            ["positionModifiedAt"] = 799999999.125, ["titleModifiedAt"] = 799999998.75,
            ["splitGroupID"] = SwiftId(Guid.NewGuid()), ["keepsPageLoaded"] = true,
            ["faviconURL"] = "https://example.com/favicon.ico", ["iconAccent"] = new JsonObject { ["future"] = "blue" },
            ["futureTabProperty"] = new JsonArray(1, 2, 3)
        };
        JsonObject savedSpace = new()
        {
            ["id"] = SwiftId(space.Value), ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString().ToUpperInvariant() },
            ["name"] = "Reading", ["symbol"] = "book", ["accent"] = "future-accent", ["accessPolicy"] = "open",
            ["branding"] = new JsonObject { ["inactivePalette"] = "preserve-me" },
            ["browsingPreferences"] = new JsonObject { ["searchProvider"] = "duckDuckGo", ["futureFlag"] = true },
            ["credentialPreferences"] = new JsonObject { ["isEnabled"] = false },
            ["tabs"] = new JsonArray(savedTab), ["selectedTabID"] = SwiftId(tab.Value),
            ["folders"] = new JsonArray(new JsonObject
            {
                ["id"] = SwiftId(folder), ["title"] = "Articles", ["location"] = "saved",
                ["isCollapsed"] = true, ["symbol"] = "book", ["color"] = new JsonObject { ["red"] = 0.7 }
            }),
            ["archivedTabs"] = new JsonArray(), ["history"] = new JsonArray(new JsonObject
            {
                ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(), ["url"] = "https://example.com/article",
                ["title"] = "Earlier visit", ["firstVisitedAt"] = 799999990.0, ["lastVisitedAt"] = 800000000.0,
                ["visitCount"] = 4, ["futureHistoryProperty"] = true
            })
        };
        JsonObject savedWindow = new()
        {
            ["id"] = SwiftId(window.Value), ["selectedSpaceID"] = SwiftId(space.Value),
            ["selectedTabIDsBySpace"] = empty ? new JsonArray() : new JsonArray(SwiftId(space.Value), SwiftId(tab.Value)),
            ["capturedSpaceIDs"] = new JsonArray(SwiftId(space.Value)), ["sidebarWidth"] = 271.5,
            ["extensionSidebarBySpace"] = new JsonArray(SwiftId(space.Value), new JsonObject { ["width"] = 300 })
        };
        return (new JsonObject
        {
            ["workspaceId"] = Guid.NewGuid().ToString(), ["formatVersion"] = 1,
            ["session"] = new JsonObject
            {
                ["spaces"] = new JsonArray(savedSpace), ["selectedSpaceID"] = SwiftId(space.Value),
                ["defaultSpaceID"] = SwiftId(space.Value), ["disposableSeedMarker"] = Guid.NewGuid().ToString(),
                ["futureSessionProperty"] = "survives"
            },
            ["windows"] = new JsonArray(savedWindow)
        }, space, tab, window);
    }

    [Fact]
    public void LegacySessionPreservesMetadataAndUsesFreshNativeIdentitiesAfterRestart()
    {
        var fixture = SavedSession(); var document = new LegacySessionDocument(fixture.Document);
        var ids = new SystemIdSource(); var state = document.Read(ids);
        var workspace = BrowserWorkspace.Restore(state, ids, new SystemClock());
        var tab = workspace.Space(fixture.Space).Tab(fixture.Tab);
        Assert.Equal(TabPhase.Dormant, tab.Phase); Assert.Null(tab.PageId);
        Assert.True(tab.KeepsPageLoaded); Assert.Equal("My reading", tab.DisplayTitle);
        Assert.Equal("https://example.com/", tab.SavedUrl);
        workspace.RenameTab(fixture.Space, fixture.Tab, "Updated title");
        var output = document.Write(workspace.Capture());
        var inputSpace = fixture.Document["session"]!["spaces"]![0]!;
        var outputSpace = output["session"]!["spaces"]![0]!;
        foreach (var key in new[] { "branding", "browsingPreferences", "credentialPreferences", "history" })
            Assert.True(JsonNode.DeepEquals(inputSpace[key], outputSpace[key]), key);
        Assert.True(JsonNode.DeepEquals(inputSpace["folders"]![0]!["color"], outputSpace["folders"]![0]!["color"]));
        Assert.True(outputSpace["folders"]![0]!["isCollapsed"]!.GetValue<bool>());
        Assert.Equal("survives", output["session"]!["futureSessionProperty"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(inputSpace["tabs"]![0]!["futureTabProperty"], outputSpace["tabs"]![0]!["futureTabProperty"]));
        Assert.Equal("Updated title", outputSpace["tabs"]![0]!["customTitle"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(fixture.Document["windows"], output["windows"]));
        var restored = new LegacySessionDocument(output).Read(ids);
        Assert.Equal(state.Spaces[0].ProfileId, restored.Spaces[0].ProfileId);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void RestoredWindowCreatesOnlyItsSelectedPageAndPreservesExplicitEmpty(bool empty)
    {
        var f = SavedSession(empty); var core = new BrowserKernel(Adapters, initialState: f.Document);
        var effects = core.Process(Message("core.open_window", new() { ["windowId"] = f.Window.Value.ToString() }));
        Assert.Equal(empty ? 0 : 1, effects.Count(e => e.Type == "engine.create_page"));
        Assert.Equal(empty ? null : f.Tab, core.Workspace.Window(f.Window).Selection(f.Space));
        Assert.Equal(empty ? TabPhase.Dormant : TabPhase.Creating, core.Workspace.Space(f.Space).Tab(f.Tab).Phase);
    }

    [Fact]
    public void LoadingOnlyObservationDoesNotReserializeTheDurableSession()
    {
        var f = SavedSession(); f.Document["futureLargeProperty"] = new string('x', 2_000_000);
        var storage = new Adapter("services", "services", "test.storage", "1",
            new Dictionary<string, Capability> { ["session-storage"] = new("supported", 1, "test", [], "test") });
        var core = new BrowserKernel(Adapters.Append(storage).ToArray(), initialState: f.Document, persistSession: true);
        var opened = core.Process(Message("core.open_window", new() { ["windowId"] = f.Window.Value.ToString() }));
        var create = opened.Single(e => e.Type == "engine.create_page");
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var tab = core.Workspace.Space(f.Space).Tab(f.Tab);
        var payload = Observation(create);
        payload["url"] = tab.Url; payload["title"] = tab.Title; payload["isLoading"] = true;
        payload["canGoBack"] = false; payload["canGoForward"] = false; payload["committed"] = false;
        var message = Message("engine.page_changed", payload, "engine");
        long before = GC.GetAllocatedBytesForCurrentThread();
        var output = core.Process(message);
        long allocated = GC.GetAllocatedBytesForCurrentThread() - before;
        Assert.True(allocated < 256_000, $"Loading update allocated {allocated} bytes; durable metadata must stay out of this path.");
        var update = Assert.Single(output);
        Assert.Equal("ui.tab_changed", update.Type);
        Assert.True(update.Payload["tab"]!["isLoading"]!.GetValue<bool>());
        Assert.Null(update.Payload["spaces"]);
    }

    [Fact]
    public void DiscardingAnUnconnectedSceneRemovesOnlyItsSavedWindow()
    {
        var f = SavedSession(); f.Document["windows"]![0]!["platformSceneId"] = "native-scene-session";
        var core = new BrowserKernel(Adapters, initialState: f.Document);
        Assert.Equal("native-scene-session", Assert.Single(core.Workspace.Capture().Windows).PlatformSceneId);
        var effects = core.Process(Message("core.close_window", new() { ["windowId"] = f.Window.Value.ToString() }));
        Assert.Empty(core.Workspace.Capture().Windows);
        Assert.Equal(f.Tab, Assert.Single(core.Workspace.Space(f.Space).Tabs).Id);
        Assert.DoesNotContain(effects, e => e.Kind == "effect");
        Assert.Contains(effects, e => e.Type == "core.operation_completed");
    }

    [Fact]
    public void ConflictingRestoredWindowsCannotOwnTheSameNativePage()
    {
        var f = SavedSession(); var second = new WindowId(Guid.NewGuid());
        var copied = (JsonObject)f.Document["windows"]![0]!.DeepClone(); copied["id"] = SwiftId(second.Value);
        ((JsonArray)f.Document["windows"]!).Add((JsonNode)copied);
        var core = new BrowserKernel(Adapters, initialState: f.Document);
        core.Process(Message("core.open_window", new() { ["windowId"] = f.Window.Value.ToString() }));
        var effects = core.Process(Message("core.open_window", new() { ["windowId"] = second.Value.ToString() }));
        Assert.Equal(f.Tab, core.Workspace.Window(f.Window).Selection(f.Space));
        Assert.Null(core.Workspace.Window(second).Selection(f.Space));
        Assert.DoesNotContain(effects, e => e.Type == "engine.create_page");
        Assert.Equal(f.Window, core.Workspace.PresentingWindow(f.Space, f.Tab)!.Id);
    }

    [Fact]
    public void UnknownAccessPolicyCannotRestoreOrOpenAnEnginePage()
    {
        var f = SavedSession(); f.Document["session"]!["spaces"]![0]!["accessPolicy"] = "future-restricted-policy";
        var core = new BrowserKernel(Adapters, initialState: f.Document);
        var effects = core.Process(Message("core.open_window", new() { ["windowId"] = f.Window.Value.ToString() }));
        Assert.DoesNotContain(effects, e => e.Type == "engine.create_page");
        Assert.Contains(core.Process(Message("core.select_tab", Selection(f.Window, f.Space, f.Tab))),
            e => e.Payload["code"]?.GetValue<string>() == "space_locked");
        Assert.Null(core.Workspace.Space(f.Space).Tab(f.Tab).PageId);
        Assert.Contains(core.Process(Message("core.unlock_space", new()
        { ["windowId"] = f.Window.Value.ToString(), ["spaceId"] = f.Space.Value.ToString() })),
            e => e.Payload["code"]?.GetValue<string>() == "unsupported_access_policy");
    }

    private static Adapter[] PersistenceAdapters => [.. Adapters, new("services", "services", "test-storage", "1",
        new Dictionary<string, Capability> { ["session-storage"] = new("supported", 1, "test", [], "contract suite") })];

    [Fact]
    public void SavesCoalesceBehindAcknowledgedRevisionsAndRejectForgedAcknowledgments()
    {
        var core = new BrowserKernel(PersistenceAdapters, persistSession: true); var id = Guid.NewGuid();
        var first = core.Process(Message("core.open_window", new() { ["windowId"] = id.ToString() }))
            .Single(e => e.Type == "services.save_session");
        var space = core.Workspace.Spaces[0];
        var rename = Message("core.rename_space", new() { ["spaceId"] = space.Id.Value.ToString(), ["name"] = "Updated" });
        Assert.DoesNotContain(core.Process(rename), e => e.Type == "services.save_session");
        JsonObject Ack(Outgoing e) => new() { ["revision"] = e.Payload["revision"]!.DeepClone() };
        Assert.Contains(core.Process(Message("services.session_saved", Ack(first), "services", Guid.NewGuid(), first.CorrelationId)),
            e => e.Type == "core.operation_failed");
        var second = core.Process(Message("services.session_saved", Ack(first), "services", first.Id, first.CorrelationId))
            .Single(e => e.Type == "services.save_session");
        Assert.Equal("Updated", second.Payload["state"]!["session"]!["spaces"]![0]!["name"]!.GetValue<string>());
        Assert.Equal("2", second.Payload["revision"]!.GetValue<string>());
        core.Process(Message("services.save_failed", Ack(second), "services", second.Id, second.CorrelationId));
        Assert.True(core.SaveFailed); Assert.Equal(0, core.PendingEffectCount);
        var retry = core.Process(Message("core.retry_save", new())).Single(e => e.Type == "services.save_session");
        Assert.False(core.SaveFailed);
        core.Process(Message("services.session_saved", Ack(retry), "services", retry.Id, retry.CorrelationId));
        Assert.Equal(0, core.PendingEffectCount);
        Assert.DoesNotContain(core.Process(Message("core.snapshot", new())), e => e.Type == "services.save_session");
    }

    [Fact]
    public void DuplicatePersistedProfileRejectsTheImportBeforeAnyNativeWork()
    {
        var f = SavedSession(); var other = f.Document["session"]!["spaces"]![0]!.DeepClone();
        other["id"] = SwiftId(Guid.NewGuid()); other["tabs"] = new JsonArray(); other["folders"] = new JsonArray(); other["history"] = new JsonArray();
        f.Document["session"]!["spaces"]!.AsArray().Add(other);
        Assert.Throws<BrowserRuleException>(() => new BrowserKernel(Adapters, initialState: f.Document));
    }

    [Fact]
    public void FailedSaveBlocksShutdownUntilTheCurrentStateIsSuccessfullyRetried()
    {
        var runtime = new CoreRuntime(new(Session, 8192, 4096, PersistSession: true));
        foreach (var role in new[] { "ui", "engine", "platform" }) Assert.Equal(0, runtime.Register(Descriptor(role)));
        var descriptor = JsonNode.Parse(Descriptor("services"))!;
        descriptor["capabilities"]!["session-storage"] = descriptor["capabilities"]!["pages"]!.DeepClone();
        Assert.Equal(0, runtime.Register(Encoding.UTF8.GetBytes(descriptor.ToJsonString())));
        Assert.Equal(0, runtime.Start());
        Assert.Equal(0, runtime.Post(Input(Guid.NewGuid())));
        Envelope Next(string type)
        {
            for (int attempt = 0; attempt < 20; attempt++)
            {
                Assert.Equal(0, runtime.WaitOutput(2000));
                runtime.Read([], out int count); var bytes = new byte[count]; Assert.Equal(0, runtime.Read(bytes, out _));
                var e = Protocol.Decode(bytes); if (e.Type == type) return e;
            }
            throw new Exception("Expected output was not produced");
        }
        void Post(string type, string sender, ulong sequence, JsonObject body, Envelope? cause = null)
        {
            var id = Guid.NewGuid();
            var node = JsonNode.Parse(Protocol.Encode(Session, id, cause?.CorrelationId ?? id, cause?.Id, "core", sequence,
                sender == "ui" ? "command" : "observation", type, body))!;
            node["sender"] = sender;
            Assert.Equal(0, runtime.Post(Encoding.UTF8.GetBytes(node.ToJsonString())));
        }
        var saving = Next("services.save_session");
        runtime.BeginShutdown();
        Post("services.save_failed", "services", 1, new() { ["revision"] = saving.Payload.GetProperty("revision").GetString() }, saving);
        Assert.Equal("persistence_failed", Next("core.shutdown_blocked").Payload.GetProperty("code").GetString());
        Assert.Equal(CoreStatus.Timeout, runtime.WaitStopped(0));
        Post("core.retry_save", "ui", 2, new());
        var retry = Next("services.save_session");
        Post("services.session_saved", "services", 2, new() { ["revision"] = retry.Payload.GetProperty("revision").GetString() }, retry);
        Stop(runtime);
    }
}
