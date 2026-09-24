using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Tests;

/// A clock a test sets.
internal sealed class TestClock(DateTimeOffset now) : IClock {
    #region Variables

    public DateTimeOffset Now { get; set; } = now;

    #endregion
}

/// The identities a test supplied, in order, and fresh ones once they run out.
internal sealed class TestIds : IIdSource {
    #region Variables

    private readonly Queue<Guid> supplied = [];

    #endregion

    #region Actions - Identity supply

    public void Supply(IEnumerable<Guid> ids) {
        foreach (var id in ids) supplied.Enqueue(id);
    }

    public Guid Next() => supplied.TryDequeue(out var id) ? id : Guid.NewGuid();

    #endregion
}

/// The recorded session commands whose operations are typed intents now. A
/// recorded step keeps the request the command sent, so the step runs as the
/// intent that replaced it, at the time the request names.
internal static class RecordedIntents {
    #region Actions - Reading

    /// The intent a recorded request became, issued in `workspace` from
    /// `window`, or null for a request that is still a session command.
    public static SessionIntent? Typed(JsonObject request, Guid workspace, Guid? window) {
        var arguments = request["arguments"] as JsonObject ?? [];
        Guid Id(string key) => Guid.Parse(request[key]!.GetValue<string>());
        Guid Argument(string key) => Guid.Parse(arguments[key]!.GetValue<string>());
        Guid? Optional(string key) => arguments[key] is { } value ? Guid.Parse(value.GetValue<string>()) : null;
        BrandColor? Color(JsonNode? value) => value is JsonObject color ? StoredSessionCodec.DecodeColor(color) : null;
        return request["operation"]!.GetValue<string>() switch {
            "archive.restore" => new RestoreArchivedTab(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId")),
            "records.sweep" => new SweepExpiredRecords(workspace),
            "folder.create" => new CreateFolder(workspace, Id("spaceId"), Argument("folderId"),
                TabPlacement.Named(arguments["placement"]!.GetValue<string>())!, Optional("parentId"), arguments["title"]?.GetValue<string>(),
                Color(arguments["color"]), arguments["symbol"]?.GetValue<string>(),
                [.. (arguments["tabIds"] as JsonArray ?? []).Select(id => Guid.Parse(id!.GetValue<string>()))],
                arguments["detach"]?.GetValue<bool>() == true),
            "split.join" => new JoinSplit(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"), Argument("targetId"),
                arguments["index"]?.GetValue<int>(), [.. (arguments["copyObservations"] as JsonArray ?? []).Select(page =>
                    new SourcePage(Guid.Parse(page!["tabId"]!.GetValue<string>()), page["url"]?.GetValue<string>(),
                        page["title"]!.GetValue<string>()))]),
            "split.title" => new NameSplit(workspace, Id("spaceId"), Argument("groupId"), arguments["value"]?.GetValue<string>()),
            "split.tint" => new TintSplit(workspace, Id("spaceId"), Argument("groupId"), Color(arguments["value"])),
            _ => null
        };
    }

    /// The identities a recorded request gave the records it made, which the
    /// core now gives them itself.
    public static IEnumerable<Guid> Identities(JsonObject request) =>
        (request["arguments"]?["ids"] as JsonArray ?? []).Select(id => Guid.Parse(id!.GetValue<string>()));

    /// When a recorded request ran.
    public static DateTimeOffset Time(JsonObject request) => StoredSessionCodec.Date(request["now"]!.GetValue<double>());

    #endregion
}
