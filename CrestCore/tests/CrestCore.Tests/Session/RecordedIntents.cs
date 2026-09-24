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
        Guid Id(string key) => Guid.Parse(request[key]!.GetValue<string>());
        Guid Argument(string key) => Guid.Parse(request["arguments"]![key]!.GetValue<string>());
        return request["operation"]!.GetValue<string>() switch {
            "archive.restore" => new RestoreArchivedTab(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId")),
            "records.sweep" => new SweepExpiredRecords(workspace),
            _ => null
        };
    }

    /// When a recorded request ran.
    public static DateTimeOffset Time(JsonObject request) => StoredSessionCodec.Date(request["now"]!.GetValue<double>());

    #endregion
}
