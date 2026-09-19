using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    private static JsonObject RecordsQuery(WindowId window, SpaceId space, string kind = "history", string query = "", int offset = 0) => new()
    {
        ["windowId"] = window.Value.ToString(), ["spaceId"] = space.Value.ToString(), ["kind"] = kind,
        ["queryId"] = Guid.NewGuid().ToString(), ["query"] = query, ["offset"] = offset
    };
    [Fact]
    public void RecordsQueriesAreBoundedReadOnlyAndDoNotMaterializePages()
    {
        var fixture = SavedSession(); var savedHistory = fixture.Document["session"]!["spaces"]![0]!["history"]!.AsArray();
        var template = savedHistory[0]!.DeepClone(); savedHistory.Clear();
        for (var index = 0; index < 125; index++)
        {
            var item = template.DeepClone(); item["id"] = Guid.NewGuid().ToString().ToUpperInvariant();
            item["url"] = $"https://example.com/{index}"; item["title"] = $"Reading {index}"; savedHistory.Add(item);
        }
        var core = new BrowserKernel(Adapters, initialState: fixture.Document); core.Workspace.AddWindow(fixture.Window);
        var first = Assert.Single(core.Process(Message("core.query_records", RecordsQuery(fixture.Window, fixture.Space))));
        Assert.Equal("ui.records", first.Type); Assert.Equal(125, first.Payload["total"]!.GetValue<int>());
        Assert.Equal(50, first.Payload["items"]!.AsArray().Count);
        var tail = Assert.Single(core.Process(Message("core.query_records", RecordsQuery(fixture.Window, fixture.Space, offset: 100))));
        Assert.Equal(25, tail.Payload["items"]!.AsArray().Count);
        var filtered = Assert.Single(core.Process(Message("core.query_records", RecordsQuery(fixture.Window, fixture.Space, query: "READING 124"))));
        Assert.Equal(1, filtered.Payload["total"]!.GetValue<int>());
        Assert.Null(core.Workspace.Space(fixture.Space).Tab(fixture.Tab).PageId);
        core.Workspace.Space(fixture.Space).SetAccessPolicy(true);
        var locked = Assert.Single(core.Process(Message("core.query_records", RecordsQuery(fixture.Window, fixture.Space))));
        Assert.Equal("space_locked", locked.Payload["code"]!.GetValue<string>());
        Assert.Null(locked.Payload["items"]);
    }
    [Fact]
    public void RecordActionsUseOwnedIdsAndNativePagesRoundTripWithoutEnginePages()
    {
        var fixture = SavedSession(); var core = new BrowserKernel(Adapters, initialState: fixture.Document);
        core.Workspace.AddWindow(fixture.Window); var space = core.Workspace.Space(fixture.Space);
        var open = new JsonObject { ["windowId"] = fixture.Window.Value.ToString(), ["spaceId"] = fixture.Space.Value.ToString(), ["kind"] = "history" };
        var output = core.Process(Message("core.open_records", open));
        Assert.DoesNotContain(output, e => e.Type == "engine.create_page");
        var native = Assert.Single(space.Tabs, t => t.NativeKind == "history");
        Assert.Equal(native.Id, core.Workspace.Window(fixture.Window).Selection(space.Id));
        Assert.Contains(output, e => e.Type == "platform.assign_surface" && e.Payload["panes"]![0]!["kind"]!.GetValue<string>() == "history");
        core.Process(Message("core.open_records", open)); Assert.Single(space.Tabs, t => t.NativeKind == "history");
        var visit = Assert.Single(space.History);
        var target = new JsonObject { ["windowId"] = fixture.Window.Value.ToString(), ["spaceId"] = space.Id.Value.ToString(), ["entryId"] = visit.Id.ToString() };
        var page = core.Process(Message("core.open_history_entry", target)).Single(e => e.Type == "engine.create_page");
        Assert.Equal(visit.Url, page.Payload["url"]!.GetValue<string>());
        core.Process(Message("core.delete_history_entry", target)); Assert.Empty(space.History);
        var checkpoint = new LegacySessionDocument(fixture.Document).Write(core.Workspace.Capture());
        var restored = new LegacySessionDocument(checkpoint).Read(new SystemIdSource());
        Assert.Contains(restored.Spaces[0].Tabs, t => t.Id == native.Id && t.NativeKind == "history" && t.Kind == TabKind.Native);
        Assert.Empty(restored.Spaces[0].History);
    }
    [Fact]
    public void BorrowedHistoryNeverQueriesOrClearsTheSourceRecords()
    {
        var fixture = SavedSession(); var core = new BrowserSessionKernel(WorkspaceAdapters, initialState: fixture.Document);
        core.Workspace.AddWindow(fixture.Window); var source = core.Workspace.Space(fixture.Space);
        var (borrowed, window, _) = CreateWorkspace(core, core.Workspace, "borrowed");
        var records = core.Process(Message("core.query_records", RecordsQuery(window, source.Id))).Single(e => e.Type == "ui.records");
        Assert.Empty(records.Payload["items"]!.AsArray());
        core.Process(Message("core.clear_history", new() { ["windowId"] = window.Value.ToString(), ["spaceId"] = source.Id.Value.ToString() }));
        Assert.Single(source.History); Assert.Empty(borrowed.Space(source.Id).History);
        var forged = core.Process(Message("core.open_history_entry", new()
        { ["windowId"] = window.Value.ToString(), ["spaceId"] = source.Id.Value.ToString(), ["entryId"] = source.History[0].Id.ToString() }));
        Assert.Contains(forged, e => e.Payload["code"]?.GetValue<string>() == "unknown_history_entry");
        Assert.Empty(borrowed.Space(source.Id).Tabs);
    }
    [Fact]
    public void RecordResultsStreamWithinTheRegisteredTransportBudget()
    {
        var fixture = SavedSession(empty: true); var history = fixture.Document["session"]!["spaces"]![0]!["history"]!.AsArray();
        var template = history[0]!.DeepClone(); history.Clear();
        for (var index = 0; index < 50; index++)
        {
            var record = template.DeepClone(); record["id"] = Guid.NewGuid().ToString().ToUpperInvariant();
            record["title"] = new string('x', 512); history.Add(record);
        }
        var runtime = new CoreRuntime(new(Session, 8192, 4096, InitialState: fixture.Document));
        foreach (var role in new[] { "ui", "engine", "platform" }) Assert.Equal(0, runtime.Register(Descriptor(role)));
        Assert.Equal(0, runtime.Start());
        byte[] Command(string type, JsonObject payload, ulong sequence)
        {
            var node = JsonNode.Parse(Input(Guid.NewGuid(), sequence))!; node["type"] = type; node["payload"] = payload;
            return System.Text.Encoding.UTF8.GetBytes(node.ToJsonString());
        }
        Assert.Equal(0, runtime.Post(Command("core.open_window", new() { ["windowId"] = fixture.Window.Value.ToString() }, 1)));
        Assert.Equal(0, runtime.Post(Command("core.query_records", RecordsQuery(fixture.Window, fixture.Space), 2)));
        using var data = new MemoryStream(); CrestCore.Contracts.Envelope? begin = null; var completed = false; var chunks = 0;
        for (var attempt = 0; attempt < 100 && !completed; attempt++)
        {
            Assert.Equal(0, runtime.WaitOutput(2000)); runtime.Read([], out var length); Assert.InRange(length, 1, 4096);
            var bytes = new byte[length]; Assert.Equal(0, runtime.Read(bytes, out _));
            var message = CrestCore.Contracts.Protocol.Decode(bytes);
            if (message.Type == "ui.records_begin") begin = message;
            else if (message.Type == "ui.records_chunk")
            {
                Assert.NotNull(begin); Assert.Equal(begin.Id, message.CausationId);
                Assert.Equal(begin.Id.ToString(), message.Payload.GetProperty("recordsId").GetString());
                Assert.Equal(chunks++, message.Payload.GetProperty("index").GetInt32());
                data.Write(Convert.FromBase64String(message.Payload.GetProperty("data").GetString()!));
            }
            else if (message.Type == "ui.records_commit")
            {
                Assert.NotNull(begin); Assert.Equal(begin.Id, message.CausationId);
                Assert.Equal(begin.Payload.GetProperty("chunkCount").GetInt32(), chunks);
                Assert.Equal(begin.Payload.GetProperty("sha256").GetString(),
                    Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(data.ToArray())));
                Assert.Equal(50, JsonNode.Parse(data.ToArray())!["items"]!.AsArray().Count); completed = true;
            }
            Assert.NotEqual("core.operation_failed", message.Type);
        }
        Assert.True(completed); Stop(runtime);
    }

    [Fact]
    public void LatePageTitleUpdatesHistoryWithoutCreatingAnotherVisit()
    {
        var core = new BrowserKernel(Adapters); var window = new WindowId(Guid.NewGuid());
        core.Workspace.AddWindow(window); var space = core.Workspace.Spaces[0]; var create = Open(core, window, space.Id);
        core.Process(Message("engine.page_created", Observation(create), "engine", create.Id, create.CorrelationId));
        var observed = Observation(create); observed["url"] = "https://example.com/"; observed["title"] = "example.com";
        observed["isLoading"] = true; observed["canGoBack"] = false; observed["canGoForward"] = false; observed["committed"] = true;
        core.Process(Message("engine.page_changed", observed, "engine"));
        var first = Assert.Single(space.History);
        observed["title"] = "Example Domain"; observed["isLoading"] = false; observed["committed"] = false;
        var output = core.Process(Message("engine.page_changed", observed, "engine"));
        var updated = Assert.Single(space.History);
        Assert.Equal("Example Domain", updated.Title); Assert.Equal(first.VisitedAt, updated.VisitedAt);
        Assert.Equal(first.VisitCount, updated.VisitCount); Assert.Equal(first.Id, updated.Id);
        Assert.True(output.Single(e => e.Type == "ui.tab_changed").Payload["recordsChanged"]!.GetValue<bool>());
    }

}
