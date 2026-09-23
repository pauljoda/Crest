using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private static readonly DateTimeOffset RecordEpoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    #endregion

    #region Actions - Records

    // The caller sends intent and what its window shows. Existing history and
    // archive entries come from the authority; only changed read models and the
    // window's follow-up selection hint cross back.
    private NativeSessionCommand PrepareRecordCommand(ulong expected, JsonObject request) {
        var operation = SessionOperationCodes.Parse(request["operation"]!.GetValue<string>());
        var args = request["arguments"]!.AsObject();
        var now = request["now"]!.GetValue<double>();
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidDate);
        var target = request["spaceId"] is null ? (Guid?)null : Id(request["spaceId"]);
        if (target is { } id) _ = TransferSpace(id, Id(request["profileId"]));
        else if (operation is not (SessionOperation.RecordsSweep or SessionOperation.RecordsCleanup))
            throw new BrowserRuleException(BrowserRuleCodes.MissingSpaceIdentity);
        var view = SessionView.Decode(request[SessionView.Key]);
        var hint = new SessionSelectionHint();
        var changes = new JsonArray();
        var spaces = document.Spaces.Select(original => {
            var spaceId = Id(original.Metadata["id"]);
            if (target is { } requested && requested != spaceId || PendingDeletion(document.Metadata, spaceId) is not null)
                return original;
            var fields = original.Metadata.DeepClone().AsObject();
            var sections = original.Sections.ToDictionary(pair => pair.Key, pair => pair.Value);
            var change = new JsonObject {
                ["spaceId"] = spaceId.ToString("D"),
                ["profileId"] = Id(fields["profile"]!["id"]).ToString("D")
            };
            if (SessionOperationCodes.IsHistory(operation))
                EditHistory(operation, args, now, sections, change);
            else if (SessionOperationCodes.IsSplitMetadata(operation))
                EditSplitMetadata(operation, args, now, fields, sections, change);
            else {
                SessionEditArguments? editArguments = null;
                if (operation == SessionOperation.ArchiveRestore) {
                    var tabId = Id(args["tabId"]);
                    var archiveIndex = Array.FindIndex(sections[SpaceSections.ArchivedTabsSection].ToArray(), a => Id(a["tab"]!["id"]) == tabId);
                    if (archiveIndex < 0) throw new BrowserRuleException(BrowserRuleCodes.UnknownArchivedTab);
                    var archived = sections[SpaceSections.ArchivedTabsSection][archiveIndex];
                    editArguments = new() { Tab = new SessionTabRecord(archived["tab"]!.AsObject()) };
                    sections[SpaceSections.ArchivedTabsSection] = sections[SpaceSections.ArchivedTabsSection].Where((_, index) => index != archiveIndex).ToArray();
                    change["removedArchiveIndices"] = new JsonArray(JsonValue.Create(archiveIndex));
                } else if (operation is SessionOperation.RecordsSweep or SessionOperation.RecordsCleanup) {
                    var term = fields["browsingPreferences"]?["currentTabCleanupPolicy"]?.GetValue<string>();
                    var policy = Enum.TryParse<CurrentTabCleanup>(term, true, out var parsed) && Enum.IsDefined(parsed)
                        ? parsed : CurrentTabCleanup.After12Hours;
                    // Launch sweeps before any window is on screen, so the caller
                    // names every tab its restored windows show.
                    if ((RetentionPreferences.Default with { CurrentTabs = policy }).TabLifetime is { } lifetime)
                        editArguments = new() { Lifetime = lifetime.TotalSeconds, TabIds = KeptTabs(args) };
                } else throw new BrowserRuleException(BrowserRuleCodes.UnknownRecordCommand);
                if (editArguments is not null) {
                    var compact = fields.DeepClone().AsObject();
                    foreach (var section in Sections)
                        compact[section] = new JsonArray(section is SpaceSections.HistorySection or SpaceSections.ArchivedTabsSection ? []
                            : sections[section].Select(n => n.DeepClone()).ToArray());
                    // Cleanup keeps the tab this window shows; a restored tab is the
                    // one it should show next.
                    var editRequest = SessionEditRequest.Create(
                        operation == SessionOperation.ArchiveRestore ? SessionOperation.TabRestoreArchive : SessionOperation.TabCleanup,
                        compact, editArguments, now, view.Tab(spaceId));
                    var edited = SessionEditResult.Decode(NativeSessionEditor.Evaluate(editRequest.Encode()));
                    var result = edited.Space;
                    if (operation == SessionOperation.ArchiveRestore || !JsonNode.DeepEquals(compact[SpaceSections.TabsSection], result[SpaceSections.TabsSection])) {
                        foreach (var section in new[] { SpaceSections.TabsSection, SpaceSections.FoldersSection })
                            sections[section] = result[section]!.AsArray().Select(n => n!.DeepClone()).ToArray();
                        fields["splitGroups"] = result["splitGroups"]?.DeepClone();
                        sections[SpaceSections.ArchivedTabsSection] = sections[SpaceSections.ArchivedTabsSection].Concat(result[SpaceSections.ArchivedTabsSection]!.AsArray().Select(n => n!.DeepClone())).ToArray();
                        var spaceHint = new SessionSelectionHint().SelectTab(view, spaceId, edited.SelectedTabId);
                        hint.SelectTab(view, spaceId, edited.SelectedTabId);
                        change["tabEdit"] = JsonNode.Parse(edited.Encode(spaceHint));
                    }
                }
                if (operation == SessionOperation.RecordsSweep) {
                    foreach (var (section, preference, date, output) in new[] {
                        (SpaceSections.HistorySection, "history", "lastVisitedAt", "removedHistory"),
                        (SpaceSections.ArchivedTabsSection, "archive", "archivedAt", "removedArchiveIndices") }) {
                        var term = fields["browsingPreferences"]?["dataRetention"]?[preference]?.GetValue<string>();
                        var policy = Enum.TryParse<DataRetention>(term, true, out var parsed) && Enum.IsDefined(parsed) ? parsed : DataRetention.Forever;
                        if (RetentionPreferences.Lifetime(policy) is not { } lifetime) continue;
                        var records = sections[section];
                        var expired = RecordRemovalPolicy.Expired(records.Select(n => n[date]!.GetValue<double>()).ToArray(), now, lifetime.TotalSeconds).ToHashSet();
                        if (expired.Count == 0) continue;
                        change[output] = section == SpaceSections.ArchivedTabsSection
                            ? new JsonArray(expired.Order().Select(i => (JsonNode?)JsonValue.Create(i)).ToArray())
                            : IDs(records.Where((_, i) => expired.Contains(i)).Select(n => RecordId(n, section)));
                        sections[section] = records.Where((_, i) => !expired.Contains(i)).ToArray();
                    }
                }
            }
            if (change.Count > 2) changes.Add((JsonNode)change);
            return new SpaceDocument(fields, sections);
        }).ToArray();
        var next = new SessionDocument(document.Metadata, spaces);
        Validate(next); ValidateBorrowedDocument(next);
        return new(this, expected, next, TransferOutput(new JsonObject {
            ["changes"] = changes,
            [SessionSelectionHint.Key] = hint.Encode()
        }));
    }

    private static IReadOnlyList<Guid>? KeptTabs(JsonObject args) =>
        args["keepTabIds"] is JsonArray kept ? kept.Select(Id).ToArray() : null;

    private static JsonArray IDs(IEnumerable<Guid> ids) => new(ids.Select(id => (JsonNode?)JsonValue.Create(id.ToString("D"))).ToArray());

    private static void EditHistory(SessionOperation operation, JsonObject args, double now,
        Dictionary<string, IReadOnlyList<JsonNode>> sections, JsonObject change) {
        var history = sections[SpaceSections.HistorySection];
        if (operation == SessionOperation.HistoryVisit) {
            var url = HistoryPolicy.Normalize(args["url"]!.GetValue<string>());
            if (url is null) return;
            var previous = history.FirstOrDefault(h => h["url"]!.GetValue<string>() == url);
            HistoryVisit? old = previous is null ? null : new(Id(previous["id"]), url, previous["title"]!.GetValue<string>(),
                RecordEpoch.AddSeconds(previous["firstVisitedAt"]!.GetValue<double>()),
                RecordEpoch.AddSeconds(previous["lastVisitedAt"]!.GetValue<double>()), previous["visitCount"]!.GetValue<int>());
            var visit = HistoryPolicy.Record(url, args["title"]?.GetValue<string>(), RecordEpoch.AddSeconds(now), Guid.NewGuid(), old);
            var entry = previous?.DeepClone().AsObject() ?? new JsonObject { ["id"] = visit.Id.ToString("D"), ["firstVisitedAt"] = now };
            entry["url"] = visit.Url; entry["title"] = visit.Title; entry["lastVisitedAt"] = now; entry["visitCount"] = visit.VisitCount;
            var next = new[] { (JsonNode)entry }.Concat(history.Where(h => Id(h["id"]) != visit.Id)).Take(HistoryPolicy.MaximumEntries).ToArray();
            var retained = next.Select(h => Id(h["id"])).ToHashSet();
            change["removedHistory"] = IDs(history.Where(h => !retained.Contains(Id(h["id"]))).Select(h => Id(h["id"])));
            change["historyEntry"] = entry.DeepClone();
            sections[SpaceSections.HistorySection] = next;
            return;
        }
        HashSet<int> removed;
        switch (operation) {
            case SessionOperation.HistoryClear: removed = Enumerable.Range(0, history.Count).ToHashSet(); break;
            case SessionOperation.HistoryRemoveUrl:
                var url = HistoryPolicy.Normalize(args["url"]!.GetValue<string>());
                removed = history.Select((h, i) => (h, i)).Where(p => url is not null && p.h["url"]!.GetValue<string>() == url).Select(p => p.i).ToHashSet();
                break;
            case SessionOperation.HistoryRemoveRange:
                removed = RecordRemovalPolicy.WithinRange(history.Select(h => h["lastVisitedAt"]!.GetValue<double>()).ToArray(),
                    args["start"]!.GetValue<double>(), args["end"]!.GetValue<double>()).ToHashSet();
                break;
            default: throw new BrowserRuleException(BrowserRuleCodes.UnknownHistoryCommand);
        }
        if (removed.Count == 0) return;
        change["removedHistory"] = IDs(history.Where((_, i) => removed.Contains(i)).Select(h => Id(h["id"])));
        sections[SpaceSections.HistorySection] = history.Where((_, i) => !removed.Contains(i)).ToArray();
    }

    private static void EditSplitMetadata(SessionOperation operation, JsonObject args, double now, JsonObject fields,
        Dictionary<string, IReadOnlyList<JsonNode>> sections, JsonObject change) {
        var id = Id(args["groupId"]);
        var run = sections[SpaceSections.TabsSection].SkipWhile(t => t["splitGroupID"] is null || Id(t["splitGroupID"]) != id)
            .TakeWhile(t => t["splitGroupID"] is not null && Id(t["splitGroupID"]) == id);
        if (run.Take(2).Count() < 2) throw new BrowserRuleException(BrowserRuleCodes.UnknownSplitGroup);
        var (field, clock) = operation switch {
            SessionOperation.SplitTitle => ("customTitle", "titleModifiedAt"),
            SessionOperation.SplitIcon => ("customIconSymbol", "iconModifiedAt"),
            SessionOperation.SplitTint => ("tint", "tintModifiedAt"),
            _ => throw new BrowserRuleException(BrowserRuleCodes.UnknownSplitCommand)
        };
        var groups = fields["splitGroups"] as JsonArray ?? new JsonArray();
        var existing = groups.FirstOrDefault(g => Id(g!["id"]) == id)?.AsObject();
        var value = args["value"]?.DeepClone();
        if (operation == SessionOperation.SplitTitle)
            value = string.IsNullOrWhiteSpace(value?.GetValue<string>()) ? null : JsonValue.Create(value!.GetValue<string>().Trim());
        if (JsonNode.DeepEquals(existing?[field], value)) return;
        var group = existing ?? new JsonObject { ["id"] = new JsonObject { ["rawValue"] = id.ToString("D") } };
        group[field] = value;
        group[clock] = NativeEditTimestamp.Normalize(now);
        if (existing is null) groups.Add((JsonNode)group);
        if (fields["splitGroups"] is null) fields["splitGroups"] = groups;
        change["splitGroups"] = groups.DeepClone();
    }

    #endregion
}
