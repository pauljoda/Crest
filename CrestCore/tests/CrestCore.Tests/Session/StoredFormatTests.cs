using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The session's stored format belongs to Swift's Codable models, and Swift reads
/// the core's projections with them. These fixtures were written by the Swift
/// encoder: a session with every optional member set, and the installed session
/// the upgrade test carries. Command answers were recorded from the core before
/// it held typed records, for the same inputs, each issued from a window that
/// showed what the step's `window` names. A step whose command is a typed
/// intent now runs as that intent at the time it recorded, and the answers of
/// the steps after it and the saved session still match.
public sealed class StoredFormatTests {
    private static JsonObject Fixture(string name) =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Session", "Fixtures", name)))!.AsObject();

    private static byte[] Bytes(JsonNode value) => Encoding.UTF8.GetBytes(value.ToJsonString());

    private static Guid? Id(JsonNode? value) => value is null ? null : Guid.Parse(value.GetValue<string>());

    private static NativeSessionAuthority Load(JsonObject session) {
        var creation = session.DeepClone().AsObject();
        creation["coreWorkspaceKind"] = "persistent";
        return new NativeSessionAuthority(Bytes(creation));
    }

    /// The checkpoint's core part with each Space's history part put back.
    private static JsonObject Written(NativeSessionAuthority authority) {
        var checkpoint = authority.Checkpoint();
        var core = JsonNode.Parse(checkpoint.Read("core"))!.AsObject();
        foreach (var space in core["spaces"]!.AsArray())
            space!["history"] = JsonNode.Parse(checkpoint.Read(space["id"]!["rawValue"]!.GetValue<string>()));
        return core;
    }

    /// The stored session and the synced records spell each member of these
    /// sets as its name, so a renamed member would misread a person's data.
    [Fact]
    public void StoredSpellingsNeverChange() {
        Assert.Equal(["pinned", "saved", "current"], TabPlacement.All.Select(placement => placement.Name));
        Assert.Equal(["autoCleanup", "closed", "deleted", "deletedOnAnotherDevice", "quickWindow", "synced"],
            ArchiveReason.All.Select(reason => reason.Name));
        Assert.Equal(["autoCleanup", "closed", "closed", "synced", "quickWindow", "synced"],
            ArchiveReason.All.Select(reason => reason.StoredReason));
        Assert.Equal([null, null, "local", "remote", null, null], ArchiveReason.All.Select(reason => reason.DeletionOrigin));
        Assert.Equal(["automatic", "pulled", "emoji"], TabIconMode.All.Select(mode => mode.Name));
        Assert.Equal("crest.emoji:", TabIconMode.EmojiPrefix);
        Assert.Equal(["startupBehavior", "offersTranslation", "automaticallyTranslates", "checksSpelling",
            "automaticallyEntersPictureInPicture", "savedTabClosePolicy", "savedTabFaviconReturnsToSavedURL", "splitFocusFollowsMouse"],
            BrowserPreference.All.Select(preference => preference.Name));
        Assert.Equal(["after12Hours", "after24Hours", "after7Days", "after30Days", "never"],
            CurrentTabCleanup.All.Select(cleanup => cleanup.Name));
        Assert.Equal(["oneDay", "oneWeek", "thirtyDays", "ninetyDays", "oneYear", "forever"], DataRetention.All.Select(retention => retention.Name));
        Assert.Equal(["after1Hour", "after6Hours", "after12Hours", "after24Hours", "never"],
            QuickWindowArchivePolicy.All.Select(policy => policy.Name));
        Assert.Equal(["balanced", "off"], ContentBlockingPolicy.All.Select(policy => policy.Name));
    }

    [Theory]
    [InlineData("maximal-session.json")]
    [InlineData("installed-session.json")]
    public void ASessionSwiftWroteIsWrittenBackUnchanged(string fixture) {
        var session = Fixture(fixture);
        var written = Written(Load(session));
        var differences = StoredJson.Differences(session, written, StoredJson.Comparison.Exact);
        Assert.True(differences.Count == 0, string.Join(Environment.NewLine, differences));
    }

    [Fact]
    public void CommandAnswersMatchWhatThePreviousCoreAnswered() {
        var session = Fixture("maximal-session.json");
        var expected = Fixture("session-answers.json");
        var authority = Load(session);
        var clock = new TestClock(DateTimeOffset.UnixEpoch);
        var ids = new TestIds();
        using var app = new CrestApp(new AppConfiguration(null), clock, ids);
        var workspace = app.AttachWorkspace(authority);
        var differences = new List<string>();
        void Compare(string name, JsonNode? actual) =>
            differences.AddRange(StoredJson.Differences(expected[name], actual, StoredJson.Comparison.AsSwiftReads, name));
        foreach (var step in Fixture("session-commands.json")["commands"]!.AsArray()) {
            var name = step!["name"]!.GetValue<string>();
            var request = step["request"]!.DeepClone().AsObject();
            Guid? window = null;
            if (step["window"] is { } shown) {
                var issuer = Guid.NewGuid();
                window = issuer;
                app.Send(new OpenWindow(issuer, workspace, Saved: false, CopyingWindowId: null, Id(shown["spaceId"]),
                    [.. shown["tabs"]!.AsArray().Select(tab => new ShownTab(Id(tab!["spaceId"])!.Value, Id(tab["tabId"])))],
                    RestoresTabs: true));
                request["windowId"] = issuer.ToString();
            }
            if (RecordedIntents.Typed(request, workspace, window) is { } intent) {
                clock.Now = RecordedIntents.Time(request);
                app.Send(intent);
            } else {
                var command = authority.PrepareCommand(Bytes(request));
                Compare(name, JsonNode.Parse(command.Output));
                if (step["commit"]!.GetValue<bool>()) command.Commit();
            }
            if (window is { } opened) app.Send(new CloseWindow(opened));
        }
        var checkpoint = authority.Checkpoint();
        var core = JsonNode.Parse(checkpoint.Read("core"))!;
        Compare("checkpoint.core", core);
        foreach (var (name, history) in expected.Where(pair => pair.Key.StartsWith("checkpoint.history.", StringComparison.Ordinal)))
            differences.AddRange(StoredJson.Differences(history,
                JsonNode.Parse(checkpoint.Read(name["checkpoint.history.".Length..])), StoredJson.Comparison.AsSwiftReads, name));
        var repair = new JsonObject {
            ["version"] = 1,
            ["operation"] = "session.repair",
            ["session"] = session.DeepClone(),
            ["now"] = 800000000.0
        };
        Compare("session.repair", JsonNode.Parse(NativeSyncQuery.Prepare(Bytes(repair))));
        Assert.True(differences.Count == 0, string.Join(Environment.NewLine, differences));
    }
}

/// Compares JSON the way a reader of the stored format does.
internal static class StoredJson {
    internal enum Comparison {
        /// Same members and values; numbers compare by value.
        Exact,
        /// As Swift's decoder reads them: an explicit null is an absent optional
        /// member, and two spellings of one UUID are the same identity.
        AsSwiftReads
    }

    public static IReadOnlyList<string> Differences(JsonNode? expected, JsonNode? actual, Comparison comparison, string path = "$") {
        var differences = new List<string>();
        Compare(expected, actual, comparison, path, differences);
        return differences;
    }

    private static void Compare(JsonNode? expected, JsonNode? actual, Comparison comparison, string path, List<string> differences) {
        if (expected is null || actual is null) {
            if (expected is not null || actual is not null) differences.Add($"{path}: expected {expected?.ToJsonString() ?? "null"}, found {actual?.ToJsonString() ?? "null"}");
            return;
        }
        switch (expected, actual) {
            case (JsonObject left, JsonObject right):
                foreach (var key in left.Select(member => member.Key).Union(right.Select(member => member.Key))) {
                    bool inLeft = left.TryGetPropertyValue(key, out var leftValue), inRight = right.TryGetPropertyValue(key, out var rightValue);
                    if (comparison == Comparison.Exact && inLeft != inRight)
                        differences.Add($"{path}.{key}: {(inLeft ? "missing" : "unexpected")}");
                    else Compare(leftValue, rightValue, comparison, $"{path}.{key}", differences);
                }
                return;
            case (JsonArray left, JsonArray right):
                if (left.Count != right.Count) { differences.Add($"{path}: expected {left.Count} items, found {right.Count}"); return; }
                for (int index = 0; index < left.Count; index++) Compare(left[index], right[index], comparison, $"{path}[{index}]", differences);
                return;
            case (JsonValue left, JsonValue right) when Same(left, right, comparison):
                return;
            default:
                differences.Add($"{path}: expected {expected.ToJsonString()}, found {actual.ToJsonString()}");
                return;
        }
    }

    private static bool Same(JsonValue left, JsonValue right, Comparison comparison) {
        if (left.GetValueKind() != right.GetValueKind()) return false;
        return left.GetValueKind() switch {
            JsonValueKind.Number => left.GetValue<double>() == right.GetValue<double>(),
            JsonValueKind.String => left.GetValue<string>() == right.GetValue<string>()
                || comparison == Comparison.AsSwiftReads && Guid.TryParse(left.GetValue<string>(), out var a)
                    && Guid.TryParse(right.GetValue<string>(), out var b) && a == b,
            _ => left.ToJsonString() == right.ToJsonString()
        };
    }
}
