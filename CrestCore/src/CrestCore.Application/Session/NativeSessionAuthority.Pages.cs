using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Page edits

    /// Applies what a page's engine reported to the Space the page lives in,
    /// as one revision saved behind and staged once page reports pause, and
    /// answers the changes the caller publishes. Reports and intents take the
    /// app's lock, so no intent holds the session while a report applies. One
    /// that no longer applies changes nothing: its Space is gone, locked or
    /// being deleted, its tab is gone, or the session takes no edits.
    internal IReadOnlyList<Change> Apply(PageEdit edit) {
        ArgumentNullException.ThrowIfNull(edit);
        (SessionState Previous, SessionState Next, SessionTabEvents Events)? applied;
        Guid workspace;
        lock (Gate) {
            applied = ApplyUnderGate(edit);
            workspace = workspaceId;
        }
        if (applied is not { } result) return [];
        QueueStage(result.Previous, result.Next, SyncStaging.PageReport);
        return [.. SessionChanges.Publish(workspace, result.Previous, result.Next), .. result.Events.Changes(workspace),
            .. edit.Announced(workspace)];
    }

    /// Gives a tab that shows no web page the address the intent's input
    /// resolves to by its Space's rules, on an engine that shows internal
    /// pages when `allowsInternalPages`, titled by its host, so a page can open
    /// for it; see `NavigateTab`. A tab that already shows a web page is left
    /// as it is.
    private SessionEdit NavigatingTab(SessionState basis, NavigateTab intent, bool allowsInternalPages) {
        var space = Editable(basis, intent.SpaceId);
        var stored = space.Tabs.FirstOrDefault(tab => tab.Id == intent.TabId) ?? throw new Rejected(new UnknownTab(intent.TabId));
        var url = AddressResolution.Loading(intent.Input, space.Settings.BrowsingPreferences, allowsInternalPages);
        var tab = BrowserTab.Restore(stored);
        if (tab.Content.IsWebPage) return new(basis, SyncStaging.PageReport);
        var address = new Uri(url);
        tab.ObserveAppearance(url, address.Host.Length > 0 ? address.Host : url);
        var tabs = space.Tabs.Select(candidate => candidate.Id == intent.TabId ? tab.State : candidate);
        return new(Replacing(basis, space with { Tabs = [.. tabs] }), SyncStaging.PageReport);
    }

    /// Starts `copy`, a new copy of `sourceId`, from the address and title
    /// the source's page shows now, preferring the page `windowId` hosts,
    /// since a page can move on before its navigation is recorded. A copy of
    /// a source without a page, or of one that is not a web page, keeps what
    /// the session holds.
    private void StartFromSourcePage(BrowserTab copy, Guid sourceId, Guid windowId, Pages? pages) {
        if (copy.Content.IsWebPage && pages?.Showing(workspaceId, windowId, sourceId) is { } shown)
            copy.ObserveAppearance(shown.Address, shown.Title);
    }

    /// Accepts `edit` and answers the states it went between, or null when it
    /// no longer applies. An edit that changes nothing is still taken: the
    /// state stays as it was. The caller holds the gate.
    private (SessionState Previous, SessionState Next, SessionTabEvents Events)? ApplyUnderGate(PageEdit edit) {
        try {
            RequireWritable();
        } catch (BrowserRuleException) {
            return null;
        }
        if (PendingDeletion(session, edit.SpaceId) is not null
            || session.Spaces.FirstOrDefault(space => space.Id == edit.SpaceId) is not { } original
            || IsLockedUnderGate(original)) return null;
        if (edit.Apply(original, Stamp(edit.At)) is not { } edited) return null;
        var events = new SessionTabEvents([], edited.Favicon);
        if (edited.Space == original) return (session, session, events);
        var next = Replacing(session, edited.Space);
        Validate(session, next);
        ValidateBorrowedSession(next);
        return (Accept(next), next, events);
    }

    #endregion
}
