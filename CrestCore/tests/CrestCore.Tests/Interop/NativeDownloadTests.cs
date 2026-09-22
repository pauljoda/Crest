using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class NativeDownloadTests {
    private static readonly string Profile = Guid.NewGuid().ToString();

    private static JsonNode Apply(NativeDownloadLedger ledger, JsonObject command) {
        command["version"] = 1;
        return JsonNode.Parse(ledger.Apply(Encoding.UTF8.GetBytes(command.ToJsonString())))!;
    }

    private static JsonNode Policy(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    [Fact]
    public void LedgerCommandsAnswerDeltasTheProjectionAppliesInPlace() {
        var ledger = new NativeDownloadLedger();
        string first = Guid.NewGuid().ToString(), second = Guid.NewGuid().ToString();
        Apply(ledger, new() { ["command"] = "begin", ["id"] = first, ["profileID"] = Profile, ["filename"] = "a.pdf", ["createdAt"] = 10.5, ["acknowledged"] = false });
        var begun = Apply(ledger, new() { ["command"] = "begin", ["id"] = second, ["profileID"] = Profile, ["filename"] = "b.pdf", ["createdAt"] = 20.25, ["acknowledged"] = true });
        Assert.True(begun["applied"]!.GetValue<bool>());
        Assert.Equal(0, begun["items"]![0]!["index"]!.GetValue<int>());
        Assert.Equal(20.25, begun["items"]![0]!["item"]!["createdAt"]!.GetValue<double>());
        Assert.True(begun["items"]![0]!["item"]!["acknowledged"]!.GetValue<bool>());

        var risk = Apply(ledger, new() {
            ["command"] = "assess_risk",
            ["id"] = first,
            ["assessment"] = new JsonObject { ["sanitizedFilename"] = "a.command", ["reasons"] = new JsonArray("executableOrInstaller") }
        });
        var item = risk["items"]![0]!;
        Assert.Equal(1, item["index"]!.GetValue<int>());
        Assert.Equal("awaitingApproval", item["item"]!["state"]!.GetValue<string>());
        Assert.Equal("a.command", item["item"]!["filename"]!.GetValue<string>());

        var transfer = Apply(ledger, new() {
            ["command"] = "transfer",
            ["id"] = first,
            ["progress"] = 0.5,
            ["telemetry"] = new JsonObject { ["bytesReceived"] = 5_000_000_000L, ["totalBytes"] = 10_000_000_000L, ["bytesPerSecond"] = 1e6, ["estimatedTimeRemaining"] = null, ["isPaused"] = false }
        });
        Assert.Equal(5_000_000_000L, transfer["items"]![0]!["item"]!["telemetry"]!["bytesReceived"]!.GetValue<long>());

        Apply(ledger, new() { ["command"] = "cancel", ["id"] = first, ["message"] = "Canceled." });
        var late = Apply(ledger, new() { ["command"] = "finish", ["id"] = first, ["finalByteCount"] = null });
        Assert.False(late["applied"]!.GetValue<bool>());
        Assert.Empty(late["items"]!.AsArray());

        var acknowledged = Apply(ledger, new() { ["command"] = "acknowledge_profile", ["profileID"] = Profile });
        Assert.Equal(first, acknowledged["items"]![0]!["item"]!["id"]!.GetValue<string>());

        var expired = Apply(ledger, new() {
            ["command"] = "expire",
            ["now"] = 1_000.0,
            ["retention"] = new JsonArray(new JsonObject { ["profileID"] = Profile, ["lifetime"] = 60.0 })
        });
        Assert.Equal([first], expired["removed"]!.AsArray().Select(id => id!.GetValue<string>()));
        Assert.Equal([Guid.Parse(second)], ledger.Items.Select(record => record.Id));
    }

    [Fact]
    public void RejectedCommandsLeaveNoAnswerToRead() {
        var ledger = new NativeDownloadLedger();
        var id = Guid.NewGuid().ToString();
        Apply(ledger, new() { ["command"] = "begin", ["id"] = id, ["profileID"] = Profile, ["filename"] = "a.pdf", ["createdAt"] = 1.0, ["acknowledged"] = false });
        Assert.NotEmpty(ledger.LastResult);

        Assert.Throws<BrowserRuleException>(() => Apply(ledger, new() { ["command"] = "begin", ["id"] = id, ["profileID"] = Profile, ["filename"] = "a.pdf", ["createdAt"] = 1.0, ["acknowledged"] = false }));
        Assert.Empty(ledger.LastResult);
        Assert.Throws<BrowserRuleException>(() => Apply(ledger, new() { ["command"] = "resurrect", ["id"] = id }));
        Assert.Throws<ProtocolException>(() => Apply(ledger, new() { ["command"] = "remove", ["id"] = id.ToUpperInvariant() }));
        Assert.Throws<ProtocolException>(() => Apply(ledger, new() {
            ["command"] = "assess_risk",
            ["id"] = id,
            ["assessment"] = new JsonObject { ["sanitizedFilename"] = "a.pdf", ["reasons"] = new JsonArray("unknownReason") }
        }));
        Assert.Single(ledger.Items);
    }

    [Fact]
    public void DownloadPolicyOperationsRoundTripTheirState() {
        var first = Policy(new() { ["operation"] = "downloads.progress", ["estimator"] = null, ["completedUnitCount"] = 0, ["totalUnitCount"] = 10_000, ["fractionCompleted"] = 0.0, ["isPaused"] = false, ["uptime"] = 0.0 });
        var second = Policy(new() { ["operation"] = "downloads.progress", ["estimator"] = first["estimator"]!.DeepClone(), ["completedUnitCount"] = 1_000, ["totalUnitCount"] = 10_000, ["fractionCompleted"] = 0.1, ["isPaused"] = false, ["uptime"] = 1.0 });
        Assert.Equal(1_000, second["telemetry"]!["bytesPerSecond"]!.GetValue<double>(), 3);
        Assert.Equal(0.1, second["progress"]!.GetValue<double>(), 3);

        var risk = Policy(new() {
            ["operation"] = "downloads.risk",
            ["suggestedFilename"] = "photo.jpg\u202Egpj.command",
            ["sanitizedFilename"] = "photo.jpggpj.command",
            ["mimeType"] = "application/octet-stream",
            ["extensionRunsCode"] = true,
            ["mimeTypeRunsCode"] = false,
            ["typesRelated"] = null,
            ["userInitiated"] = true
        });
        Assert.Equal(["executableOrInstaller", "deceptiveFilename"], risk["reasons"]!.AsArray().Select(reason => reason!.GetValue<string>()));
        Assert.True(risk["requiresConfirmation"]!.GetValue<bool>());

        var automatic = Policy(new() { ["operation"] = "downloads.automatic", ["userInitiated"] = false, ["userApprovedRetry"] = false, ["savedDecision"] = "ask", ["hasAllowedAutomaticDownload"] = true });
        Assert.Equal("requestPermission", automatic["action"]!.GetValue<string>());
        Assert.Throws<ProtocolException>(() => Policy(new() { ["operation"] = "downloads.automatic", ["userInitiated"] = false, ["userApprovedRetry"] = false, ["savedDecision"] = "maybe", ["hasAllowedAutomaticDownload"] = false }));
    }
}
