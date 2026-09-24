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
        SessionFaviconUpdate? favicon = null;
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
            case SessionOperation.TabRename:
                var renamed = edited.Tab(args.RequiredTabId); var title = args.Title;
                changed = renamed.CustomTitle != (string.IsNullOrWhiteSpace(title) ? null : title.Trim());
                if (changed) renamed.Rename(title, now);
                break;
            case SessionOperation.TabObserve:
                changed = Observe(Target(args.TabId ?? selected));
                break;
            case SessionOperation.TabIcon:
                changed = SetIcon(Target(args.RequiredTabId));
                break;
            case SessionOperation.TabFaviconCache:
                changed = CacheFavicon(Target(args.RequiredTabId));
                break;
            case SessionOperation.TabSavedLocation:
                var located = Target(args.RequiredTabId);
                changed = located is not null && args.Action switch {
                    SavedLocationAction.Replace => located.ReplaceSavedLocation(),
                    SavedLocationAction.Restore => located.RestoreSavedLocation() is not null,
                    _ => throw new ProtocolException(ProtocolErrorCodes.UnknownSessionEdit)
                };
                break;
            case SessionOperation.TabResidency:
                var resident = edited.Tab(args.RequiredTabId); var keep = args.Keep ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
                changed = resident.KeepsPageLoaded != keep; resident.SetResidency(keep);
                break;
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
        return new(edited, result, selected, selectSpace, copies, changed, favicon);

        BrowserTab? Target(Guid? id) => id is { } value ? edited.Tabs.FirstOrDefault(t => t.Id == value) : null;

        TabIconMode Mode(BrowserTab tab) => tab.State.StoredIconMode ?? TabIconMode.Inferred(tab.State.Symbol);

        // The image itself stays in the native cache. The core names the tab
        // whose stored bytes the platform must now replace or drop.
        void Assign(Guid tab, bool adopts) => favicon = new SessionFaviconUpdate(tab, adopts);

        void ClearIconAssets(BrowserTab tab) {
            tab.SetFavicon(null, null);
            Assign(tab.Id, false);
        }

        // The page settled. A rename is not touched, a blank title is the page
        // saying nothing rather than clearing the name, and an automatic icon
        // follows the page while a chosen or pulled one does not.
        bool Observe(BrowserTab? tab) {
            if (tab is null) return false;
            var url = args.Url ?? tab.Url;
            var title = args.Title;
            var accent = args.IconAccent;
            var followsPage = Mode(tab).FollowsPage;
            var updatesIcon = followsPage && (args.FaviconChanged == true || tab.State.IconAccent != accent);
            if (url == tab.Url && Blank(title) == Blank(tab.Title) && !updatesIcon) return false;
            tab.ObserveAppearance(url, title);
            if (followsPage && args.HasFavicon == true) {
                tab.SetFavicon(url, accent);
                Assign(tab.Id, true);
            }
            return true;
        }

        // Someone chose this tab's icon by hand, or handed it back to the page.
        bool SetIcon(BrowserTab? tab) {
            if (tab is null) return false;
            // An edit must name a mode this build knows; an absent or unknown term is refused.
            var mode = args.Mode ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidTabIcon);
            if (mode.RequiresFavicon && args.HasFavicon != true) return false;
            tab.SetIcon(mode.Symbol(args.Emoji) ?? throw new BrowserRuleException(BrowserRuleCodes.InvalidTabIcon));
            if (mode.RequiresFavicon) {
                tab.SetFavicon(tab.Url, args.IconAccent);
                Assign(tab.Id, true);
            } else ClearIconAssets(tab);
            tab.SetIconMode(mode);
            return true;
        }

        // A favicon that finished loading after the page moved on belongs to
        // the address it was captured from, not to whatever the tab shows now.
        bool CacheFavicon(BrowserTab? tab) {
            if (tab is null || !Mode(tab).FollowsPage || args.HasFavicon != true) return false;
            var captured = args.Url ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput);
            if (!HistoryPolicy.SamePage(tab.Url, captured)) return false;
            tab.SetIcon(TabIconMode.WebSymbol);
            tab.SetFavicon(captured, args.IconAccent);
            Assign(tab.Id, true);
            return true;
        }

        void CopyPage(Guid source, Guid copy) {
            var observation = args.CopyObservations?.FirstOrDefault(item => item.TabId == source);
            var tab = edited.Tab(copy);
            if (tab.Content.IsWebPage && observation is not null)
                tab.AdoptObservation(observation.Url, observation.Title ?? throw new ProtocolException(ProtocolErrorCodes.InvalidInput));
            copies.Add(new SessionTabCopy(source, copy));
        }
    }

    private static string? Blank(string? value) => string.IsNullOrEmpty(value) ? null : value;

    #endregion
}
