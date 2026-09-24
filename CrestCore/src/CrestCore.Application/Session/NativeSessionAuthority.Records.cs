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
        var target = request["spaceId"] is null ? (Guid?)null : Id(request["spaceId"]);
        if (target is { } id) _ = TransferSpace(id, Id(request["profileId"]));
        else if (operation is not (SessionOperation.RecordsSweep or SessionOperation.RecordsCleanup))
            throw new BrowserRuleException(BrowserRuleCodes.MissingSpaceIdentity);
        var followUp = new WindowFollowUp(IssuingWindow(request));
        var kept = device?.ShownTabs(workspaceId);
        var changes = new JsonArray();
        var spaces = session.Spaces.Select(original => {
            if (target is { } requested && requested != original.Id || PendingDeletion(session, original.Id) is not null)
                return original;
            var change = new JsonObject {
                ["spaceId"] = original.Id.ToString("D"),
                ["profileId"] = original.ProfileId.ToString("D")
            };
            var space = original;
            if (SessionOperationCodes.IsHistory(operation))
                space = EditHistory(operation, args, now, space, change);
            else if (SessionOperationCodes.IsSplitMetadata(operation))
                space = EditSplitMetadata(operation, args, StoredSessionCodec.Date(now), space, change);
            else {
                SessionEditArguments? editArguments = null;
                if (operation == SessionOperation.ArchiveRestore) {
                    var tabId = Id(args["tabId"]);
                    var archiveIndex = space.ArchivedTabs.ToList().FindIndex(archived => archived.Tab.Id == tabId);
                    if (archiveIndex < 0) throw new BrowserRuleException(BrowserRuleCodes.UnknownArchivedTab);
                    editArguments = new() { Tab = space.ArchivedTabs[archiveIndex].Tab };
                    space = space with { ArchivedTabs = space.ArchivedTabs.Where((_, index) => index != archiveIndex).ToArray() };
                    change["removedArchiveIndices"] = new JsonArray(JsonValue.Create(archiveIndex));
                } else if (operation is SessionOperation.RecordsSweep or SessionOperation.RecordsCleanup) {
                    // Cleanup keeps every tab a window shows, and at launch every
                    // tab a saved window will show.
                    if (space.Settings.BrowsingPreferences.CurrentTabCleanup.Lifetime is { } lifetime)
                        editArguments = new() { Lifetime = lifetime.TotalSeconds, TabIds = kept?.ToArray() };
                } else throw new BrowserRuleException(BrowserRuleCodes.UnknownRecordCommand);
                if (editArguments is not null) {
                    // Cleanup keeps the tab this window shows; a restored tab is the
                    // one it should show next.
                    var edited = NativeSessionEditor.Evaluate(
                        operation == SessionOperation.ArchiveRestore ? SessionOperation.TabRestoreArchive : SessionOperation.TabCleanup,
                        space, editArguments, StoredSessionCodec.Date(now), followUp.Window?.Tab(space.Id));
                    if (operation == SessionOperation.ArchiveRestore || !space.Tabs.SequenceEqual(edited.Edited.TabStates)) {
                        space = edited.Edited.Capture(space);
                        followUp.ShowTab(space.Id, edited.SelectedTabId);
                        change["tabEdit"] = edited.Answer(space);
                    }
                }
                if (operation == SessionOperation.RecordsSweep) space = SweepRecords(space, now, change);
            }
            if (change.Count > 2) changes.Add((JsonNode)change);
            return space;
        }).ToArray();
        var next = session with { Spaces = spaces };
        Validate(next); ValidateBorrowedSession(next);
        return new(this, session, next, Output(new JsonObject { ["changes"] = changes }), followUp: followUp);
    }

    private static JsonArray Identities(IEnumerable<Guid> ids) => new(ids.Select(id => (JsonNode?)JsonValue.Create(id.ToString("D"))).ToArray());

    private static double[] Seconds(IEnumerable<DateTimeOffset> dates) => dates.Select(StoredSessionCodec.Seconds).ToArray();

    /// Removes history and archive records older than the Space keeps them.
    private static SpaceState SweepRecords(SpaceState space, double now, JsonObject change) {
        if (RetentionLifetime(space.Settings.BrowsingPreferences.DataRetention.History) is { } historyLifetime) {
            var expired = RecordRemovalPolicy.Expired(Seconds(space.History.Select(entry => entry.LastVisitedAt)), now, historyLifetime).ToHashSet();
            if (expired.Count > 0) {
                change["removedHistory"] = Identities(space.History.Where((_, index) => expired.Contains(index)).Select(entry => entry.Id));
                space = space with { History = space.History.Where((_, index) => !expired.Contains(index)).ToArray() };
            }
        }
        if (RetentionLifetime(space.Settings.BrowsingPreferences.DataRetention.Archive) is { } archiveLifetime) {
            var expired = RecordRemovalPolicy.Expired(Seconds(space.ArchivedTabs.Select(archived => archived.ArchivedAt)), now, archiveLifetime).ToHashSet();
            if (expired.Count > 0) {
                change["removedArchiveIndices"] = new JsonArray(expired.Order().Select(index => (JsonNode?)JsonValue.Create(index)).ToArray());
                space = space with { ArchivedTabs = space.ArchivedTabs.Where((_, index) => !expired.Contains(index)).ToArray() };
            }
        }
        return space;
    }

    private static double? RetentionLifetime(DataRetention retention) => retention.Lifetime?.TotalSeconds;

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
        HashSet<int> removed;
        switch (operation) {
            case SessionOperation.HistoryClear: removed = Enumerable.Range(0, history.Count).ToHashSet(); break;
            case SessionOperation.HistoryRemoveUrl:
                var url = HistoryPolicy.Normalize(args["url"]!.GetValue<string>());
                removed = history.Select((entry, index) => (entry, index)).Where(pair => url is not null && pair.entry.Url == url)
                    .Select(pair => pair.index).ToHashSet();
                break;
            case SessionOperation.HistoryRemoveRange:
                removed = RecordRemovalPolicy.WithinRange(Seconds(history.Select(entry => entry.LastVisitedAt)),
                    args["start"]!.GetValue<double>(), args["end"]!.GetValue<double>()).ToHashSet();
                break;
            default: throw new BrowserRuleException(BrowserRuleCodes.UnknownHistoryCommand);
        }
        if (removed.Count == 0) return space;
        change["removedHistory"] = Identities(history.Where((_, index) => removed.Contains(index)).Select(entry => entry.Id));
        return space with { History = history.Where((_, index) => !removed.Contains(index)).ToArray() };
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
