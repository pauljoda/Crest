using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The accepted edits one stage covers, oldest first. A burst of edits stages
/// once with the newest edit's reason, but a record an edit removed is deleted
/// for the reason of the edit that removed it, so a Space deletion followed by
/// a rename still deletes the Space explicitly.
internal sealed record SyncRemovals(IReadOnlyList<SyncRemovals.Edit> Edits) {
    #region Types

    /// One accepted edit: the state it replaced, the state it made and the
    /// reason the records it removed are deleted for.
    internal sealed record Edit(SessionState Previous, SessionState Next, SyncDeletionReason Reason);

    #endregion

    #region Variables

    public static SyncRemovals None { get; } = new([]);

    private static readonly IReadOnlyDictionary<string, SyncDeletionReason> Unnamed =
        new Dictionary<string, SyncDeletionReason>(StringComparer.Ordinal);

    #endregion

    #region Actions - Edits

    /// These edits followed by `edit`.
    public SyncRemovals Adding(Edit edit) => new([.. Edits, edit]);

    /// These edits, joined by those of `later` they do not already hold.
    public SyncRemovals Joining(SyncRemovals later) => new([.. Edits, .. later.Edits.Where(edit => !Edits.Contains(edit))]);

    /// The reason each record the edits removed is deleted for, by its record
    /// name: the reason of the newest edit that removed it. Empty when every
    /// edit was made for `reason`, which the stage then gives each removal.
    public IReadOnlyDictionary<string, SyncDeletionReason> Reasons(SyncDeletionReason reason) {
        if (Edits.All(edit => edit.Reason == reason)) return Unnamed;
        var reasons = new Dictionary<string, SyncDeletionReason>(StringComparer.Ordinal);
        foreach (var edit in Edits)
            foreach (var name in Removed(edit.Previous, edit.Next)) reasons[name] = edit.Reason;
        return reasons;
    }

    /// The records `next` no longer holds that `previous` did, by the removals
    /// the session's change feed reports. A Space that is gone takes every
    /// record it held with it.
    private static IEnumerable<string> Removed(SessionState previous, SessionState next) {
        foreach (var change in SessionChanges.Publish(Guid.Empty, previous, next)) {
            switch (change) {
                case SpacesChanged spaces:
                    foreach (var id in spaces.Removed) {
                        var old = previous.Spaces.Single(space => space.Id == id);
                        // A Space the feed sends again whole names only the records it lost.
                        var resent = spaces.Added.FirstOrDefault(space => space.Id == id);
                        HashSet<string> kept = resent is null ? [] : Records(resent).ToHashSet(StringComparer.Ordinal);
                        if (resent is null) yield return Name(SyncRecordKinds.Space, id);
                        foreach (var name in Records(old).Where(name => !kept.Contains(name))) yield return name;
                    }
                    break;
                case FoldersChanged folders:
                    foreach (var id in folders.Removed) yield return Name(SyncRecordKinds.Folder, id);
                    break;
                case TabsChanged tabs:
                    foreach (var id in tabs.Removed) yield return Name(SyncRecordKinds.Tab, id);
                    break;
                case ArchiveChanged archive:
                    foreach (var id in archive.Removed) yield return Name(SyncRecordKinds.Archive, id);
                    break;
                case HistoryChanged history:
                    foreach (var id in history.Removed) yield return Name(SyncRecordKinds.History, id);
                    break;
            }
        }
    }

    /// The names of the records a Space holds besides its own.
    private static IEnumerable<string> Records(SpaceState space) =>
        space.Folders.Select(folder => Name(SyncRecordKinds.Folder, folder.Id))
            .Concat(space.Tabs.Select(tab => Name(SyncRecordKinds.Tab, tab.Id)))
            .Concat(space.ArchivedTabs.Select(archived => Name(SyncRecordKinds.Archive, archived.Tab.Id)))
            .Concat(space.History.Select(entry => Name(SyncRecordKinds.History, entry.Id)));

    /// A record's name in the journal.
    private static string Name(string kind, Guid id) => kind + ":" + id.ToString("D");

    #endregion
}
