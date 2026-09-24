using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Applies one domain edit to a Space's organization. The authority publishes the
/// result atomically, and the native store then reconciles its live pages.
/// History, existing archive records and image payloads are never part of an edit.
internal static class NativeSessionEditor {
    #region Variables

    private sealed class SuppliedIds(IReadOnlyList<Guid> values) : IIdSource {
        #region Variables

        private readonly Queue<Guid> values = new(values);

        #endregion

        #region Actions - Identity supply

        public Guid Next() => values.Dequeue();

        #endregion
    }

    #endregion

    #region Actions - Session editing

    /// Edits `space` for `operation`. The tab the issuing window shows decides
    /// only what that window shows next, which the result reports.
    public static SessionEditResult Evaluate(SessionOperation operation, SpaceState space, SessionEditArguments args,
        DateTimeOffset now, Guid? viewedTabId) {
        var edited = BrowserTabCollection.Restore(space);
        var selected = viewedTabId;
        int? index = args.Index;
        Guid? result = null;
        var selectSpace = false;
        var copies = new List<SessionTabCopy>();
        var changed = true;
        switch (operation) {
            case SessionOperation.TabPromoteTransient:
                if (args.Tab is { } transient) {
                    result = edited.PromoteTransient(transient, selected, now).Id;
                    selected = result;
                }
                selectSpace = true;
                break;
            case SessionOperation.TabArchiveTransient:
                edited.ArchiveTransient(args.RequiredTab, now);
                break;
            case SessionOperation.TabCloseDurable:
                selected = edited.CloseDurable(args.RequiredTabId, selected, args.FallbackTabId, args.ReturnToSavedUrl == true);
                break;
            case SessionOperation.TabOpen: {
                    var tab = BrowserTab.Restore(args.RequiredTab);
                    if (index is not null && args.After is not null) throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                    edited.InsertTab(tab, args.After is { } origin ? edited.InsertionIndexAfter(origin) : index);
                    result = tab.Id;
                    if (args.Select == true) { selected = tab.Id; selectSpace = true; }
                    break;
                }
            case SessionOperation.TabCopy: {
                    var source = args.RequiredTabId;
                    var copy = edited.DuplicateTab(source, new SuppliedIds(args.RequiredIds), now,
                        args.Placement ?? TabPlacement.Current, index);
                    result = copy.Id;
                    if (args.Select != false) { selected = copy.Id; selectSpace = true; }
                    CopyPage(source, copy.Id);
                    break;
                }
            case SessionOperation.TabMove:
                changed = edited.MoveTab(args.RequiredTabId, args.RequiredPlacement, args.FolderId, args.Before,
                    args.Detach == true, now);
                break;
            case SessionOperation.TabClose:
            case SessionOperation.TabDelete:
            case SessionOperation.TabClearCurrent: {
                    var deleting = operation == SessionOperation.TabDelete;
                    var clear = operation == SessionOperation.TabClearCurrent;
                    var ids = clear ? edited.Tabs.Where(t => !t.Placement.IsDurable).Select(t => t.Id).ToArray() : [args.RequiredTabId];
                    if (ids.Length == 0) throw new BrowserRuleException(BrowserRuleCodes.NoCurrentTabs);
                    selected = edited.DismissTabs(ids, selected, args.FallbackTabId, now, deleting,
                        ensureSelection: deleting || clear, resetArchivePlacement: deleting || args.ResetArchivePlacement == true);
                    break;
                }
            default: throw new ProtocolException(ProtocolErrorCodes.UnknownSessionEdit);
        }
        if (operation is SessionOperation.TabClose or SessionOperation.TabDelete or SessionOperation.TabClearCurrent
            || operation is SessionOperation.TabMove && args.Detach == true)
            edited.PruneSplitMetadata();
        return new(edited, result, selected, selectSpace, copies, changed);

        void CopyPage(Guid source, Guid copy) {
            var observation = args.CopyObservations?.FirstOrDefault(item => item.TabId == source);
            var tab = edited.Tab(copy);
            if (tab.Content.IsWebPage && observation is not null)
                tab.AdoptObservation(observation.Url, observation.Title ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput));
            copies.Add(new SessionTabCopy(source, copy));
        }
    }

    #endregion
}
