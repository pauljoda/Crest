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
            else if (SessionOperationCodes.IsSplitMetadata(operation))
                space = EditSplitMetadata(operation, args, StoredSessionCodec.Date(now), space, change);
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

    /// A split's name, icon or tint, set only on a split with at least two
    /// members; a blank name clears it. The field's clock records the edit.
    private static SpaceState EditSplitMetadata(SessionOperation operation, JsonObject args, DateTimeOffset now,
        SpaceState space, JsonObject change) {
        var id = Id(args["groupId"]);
        var run = space.Tabs.SkipWhile(tab => tab.SplitGroupId != id).TakeWhile(tab => tab.SplitGroupId == id);
        if (run.Take(2).Count() < 2) throw new BrowserRuleException(BrowserRuleCodes.UnknownSplitGroup);
        var existing = space.SplitGroups.FirstOrDefault(group => group.Id == id);
        var group = existing ?? new SplitGroupState(id);
        var value = args["value"];
        var changedAt = BrowserEditTimestamp.Normalize(now);
        var edited = operation switch {
            SessionOperation.SplitTitle => group with {
                CustomTitle = string.IsNullOrWhiteSpace(value?.GetValue<string>()) ? null : value!.GetValue<string>().Trim(),
                TitleModifiedAt = changedAt
            },
            SessionOperation.SplitIcon => group with { CustomIconSymbol = value?.GetValue<string>(), IconModifiedAt = changedAt },
            SessionOperation.SplitTint => group with {
                Tint = value is JsonObject tint ? StoredSessionCodec.DecodeColor(tint) : null,
                TintModifiedAt = changedAt
            },
            _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownSplitCommand)
        };
        var unchanged = operation switch {
            SessionOperation.SplitTitle => existing?.CustomTitle == edited.CustomTitle,
            SessionOperation.SplitIcon => existing?.CustomIconSymbol == edited.CustomIconSymbol,
            _ => existing?.Tint == edited.Tint
        };
        if (unchanged) return space;
        IReadOnlyList<SplitGroupState> groups = existing is null ? [.. space.SplitGroups, edited]
            : space.SplitGroups.Select(candidate => candidate.Id == id ? edited : candidate).ToArray();
        change["splitGroups"] = new JsonArray(groups.Select(candidate => (JsonNode?)StoredSessionCodec.Encode(candidate)).ToArray());
        return space with { SplitGroups = groups };
    }

    #endregion
}
