using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Records

    // The caller sends intent and the window that issued it. Existing history
    // and archive entries come from the authority; only changed read models
    // cross back, and the device moves the window when the command commits.
    private NativeSessionCommand PrepareRecordCommand(JsonObject request) {
        var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
        var args = request["arguments"]!.AsObject();
        var now = request["now"]!.GetValue<double>();
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidDate);
        var target = Id(request["spaceId"]);
        _ = TransferSpace(target, Id(request["profileId"]));
        var followUp = new WindowFollowUp(IssuingWindow(request));
        var changes = new JsonArray();
        var spaces = session.Spaces.Select(original => {
            if (target != original.Id) return original;
            var change = new JsonObject {
                ["spaceId"] = original.Id.ToString("D"),
                ["profileId"] = original.ProfileId.ToString("D")
            };
            var space = original;
            if (SessionOperationCodes.IsHistory(operation))
                space = EditHistory(operation, args, now, space, change);
            else throw new BrowserRuleException(BrowserRuleCodes.UnknownRecordCommand);
            if (change.Count > 2) changes.Add((JsonNode)change);
            return space;
        }).ToArray();
        var next = session with { Spaces = spaces };
        Validate(next); ValidateBorrowedSession(next);
        return new(this, session, next, Output(new JsonObject { ["changes"] = changes }), followUp: followUp);
    }

    private static JsonArray Identities(IEnumerable<Guid> ids) => new(ids.Select(id => (JsonNode?)JsonValue.Create(id.ToString("D"))).ToArray());

    private static double[] Seconds(IEnumerable<DateTimeOffset> dates) => dates.Select(StoredSessionCodec.Seconds).ToArray();

    private static SpaceState EditHistory(SessionOperation operation, JsonObject args, double now, SpaceState space,
        JsonObject change) {
        var history = space.History;
        if (operation == SessionOperation.HistoryVisit) {
            var url = HistoryPolicy.Normalize(args["url"]!.GetValue<string>());
            if (url is null) return space;
            var previous = history.FirstOrDefault(entry => entry.Url == url);
            var visit = HistoryPolicy.Record(url, args["title"]?.GetValue<string>(), StoredSessionCodec.Date(now), Guid.NewGuid(), previous);
            var next = new[] { visit }.Concat(history.Where(entry => entry.Id != visit.Id)).Take(HistoryPolicy.MaximumEntries).ToArray();
            var retained = next.Select(entry => entry.Id).ToHashSet();
            change["removedHistory"] = Identities(history.Where(entry => !retained.Contains(entry.Id)).Select(entry => entry.Id));
            change["historyEntry"] = StoredSessionCodec.Encode(visit);
            return space with { History = next };
        }
        throw new BrowserRuleException(BrowserRuleCodes.UnknownHistoryCommand);
    }

    #endregion
}
