using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// Page edits that arrived while a transaction held the session, oldest
    /// first, until it ends.
    private readonly Queue<PageEdit> deferredPageEdits = [];

    /// A call is applying the deferred page edits; any other call that finds
    /// more only adds to the queue.
    private bool applyingDeferredPageEdits;

    #endregion

    #region Actions - Page edits

    /// Applies what a page's engine reported to the Space the page lives in,
    /// as one revision saved behind and staged once page reports pause, and
    /// answers the changes the caller publishes. An edit that arrives while a
    /// transaction holds the session waits for it to end, and is applied and
    /// published then, in the order edits arrived, so no report is lost. One
    /// that no longer applies changes nothing: its Space is gone, locked or
    /// being deleted, its tab is gone, or the session takes no edits.
    internal IReadOnlyList<Change> Apply(PageEdit edit) {
        ArgumentNullException.ThrowIfNull(edit);
        (SessionState Previous, SessionState Next, SessionTabEvents Events)? applied;
        Guid workspace;
        lock (Gate) {
            if (replacement is not null || deferredPageEdits.Count > 0) {
                deferredPageEdits.Enqueue(edit);
                applied = null;
            } else applied = ApplyUnderGate(edit);
            workspace = workspaceId;
        }
        if (applied is not { } result) {
            ApplyDeferredPageEdits();
            return [];
        }
        QueueStage(result.Previous, result.Next, SyncStaging.PageReport);
        return [.. SessionChanges.Publish(workspace, result.Previous, result.Next), .. result.Events.Changes(workspace),
            .. edit.Announced(workspace)];
    }

    /// Applies the page edits that waited for a transaction, once none holds
    /// the session, and publishes each through the device. A caller that
    /// holds the gate leaves them to the call that releases it, since nothing
    /// is published under a lock.
    internal void ApplyDeferredPageEdits() {
        if (Monitor.IsEntered(Gate)) return;
        lock (Gate) {
            if (applyingDeferredPageEdits) return;
            applyingDeferredPageEdits = true;
        }
        try {
            while (true) {
                PageEdit? edit;
                (SessionState Previous, SessionState Next, SessionTabEvents Events)? applied;
                Device? target;
                Guid workspace;
                lock (Gate) {
                    if (replacement is not null || !deferredPageEdits.TryDequeue(out edit)) {
                        applyingDeferredPageEdits = false;
                        return;
                    }
                    applied = ApplyUnderGate(edit);
                    target = device;
                    workspace = workspaceId;
                }
                if (applied is not { } result) continue;
                Published(result.Previous, result.Next, followUp: null, result.Events);
                QueueStage(result.Previous, result.Next, SyncStaging.PageReport);
                foreach (var change in edit.Announced(workspace)) target?.Announce(change);
            }
        } catch {
            lock (Gate) applyingDeferredPageEdits = false;
            throw;
        }
    }

    /// Gives a tab that shows no web page the address the intent names,
    /// titled by its host, so a page can open for it; see `NavigateTab`. A tab
    /// that already shows a web page is left as it is.
    private SessionEdit NavigatingTab(SessionState basis, NavigateTab intent) {
        if (!Uri.TryCreate(intent.Url, UriKind.Absolute, out var address)) throw new Rejected(new UnsupportedAddress(intent.Url));
        var space = Editable(basis, intent.SpaceId);
        var stored = space.Tabs.FirstOrDefault(tab => tab.Id == intent.TabId) ?? throw new Rejected(new UnknownTab(intent.TabId));
        var tab = BrowserTab.Restore(stored);
        if (tab.Content.IsWebPage) return new(basis, SyncStaging.PageReport);
        tab.ObserveAppearance(intent.Url, address.Host.Length > 0 ? address.Host : intent.Url);
        var tabs = space.Tabs.Select(candidate => candidate.Id == intent.TabId ? tab.State : candidate);
        return new(Replacing(basis, space with { Tabs = [.. tabs] }), SyncStaging.PageReport);
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
        Validate(next);
        ValidateBorrowedSession(next);
        return (Accept(next), next, events);
    }

    #endregion
}
