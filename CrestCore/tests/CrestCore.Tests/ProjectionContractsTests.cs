using System.Security.Cryptography;
using System.Text.Json.Nodes;
using CrestCore.Application;
using CrestCore.Contracts;
using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests
{
    [Fact]
    public void LargeProjectionStreamsAcrossBackpressureAsOneRevision()
    {
        var fixture = SavedSession(); var tabs = fixture.Document["session"]!["spaces"]![0]!["tabs"]!.AsArray();
        var template = tabs[0]!.DeepClone(); tabs.Clear();
        for (int index = 0; index < 5000; index++)
        {
            var tab = template.DeepClone();
            tab["id"] = SwiftId(index == 0 ? fixture.Tab.Value : Guid.NewGuid());
            tab["customTitle"] = $"Retained tab {index}";
            tab["splitGroupID"] = null; tabs.Add(tab);
        }
        var runtime = new CoreRuntime(new(Session, 8192, 4096, InitialState: fixture.Document));
        foreach (var role in new[] { "ui", "engine", "platform" }) Assert.Equal(0, runtime.Register(Descriptor(role)));
        Assert.Equal(0, runtime.Start()); Assert.Equal(0, runtime.Post(Input(Guid.NewGuid())));
        using var payload = new MemoryStream(); Envelope? begin = null; ulong sequence = 0; int chunks = 0; bool completed = false;
        for (int attempt = 0; attempt < 5000 && !completed; attempt++)
        {
            Assert.Equal(0, runtime.WaitOutput(2000)); runtime.Read([], out int length);
            Assert.InRange(length, 1, 4096); var bytes = new byte[length]; Assert.Equal(0, runtime.Read(bytes, out _));
            var message = Protocol.Decode(bytes); Assert.Equal(++sequence, message.Sequence);
            if (message.Type == "ui.snapshot_begin") { Assert.Null(begin); begin = message; }
            else if (message.Type == "ui.snapshot_chunk")
            {
                Assert.NotNull(begin); Assert.Equal(begin.Id, message.CausationId); Assert.Equal(begin.CorrelationId, message.CorrelationId);
                Assert.Equal(chunks++, message.Payload.GetProperty("index").GetInt32());
                Assert.Equal(begin.Id.ToString(), message.Payload.GetProperty("snapshotId").GetString());
                payload.Write(Convert.FromBase64String(message.Payload.GetProperty("data").GetString()!));
            }
            else if (message.Type == "ui.snapshot_commit")
            {
                Assert.NotNull(begin); Assert.Equal(begin.Id, message.CausationId);
                Assert.Equal(begin.Payload.GetProperty("byteCount").GetInt32(), payload.Length);
                Assert.Equal(begin.Payload.GetProperty("chunkCount").GetInt32(), chunks);
                Assert.Equal(begin.Payload.GetProperty("sha256").GetString(), Convert.ToHexStringLower(SHA256.HashData(payload.ToArray())));
                var snapshot = JsonNode.Parse(payload.ToArray())!;
                Assert.Equal("1", snapshot["revision"]!.GetValue<string>());
                Assert.Equal(5000, snapshot["spaces"]![0]!["tabs"]!.AsArray().Count);
                Assert.True(payload.Length > 8192); completed = true;
            }
            else Assert.Equal("core.operation_completed", message.Type);
        }
        Assert.True(completed); Stop(runtime);
    }
}
