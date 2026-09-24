using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Imports

    private SessionEdit ImportingSpaces(SessionState basis, ImportSpaces intent, DateTimeOffset now, IIdSource ids) =>
        Importing(basis, intent, intent.Spaces, destinations: [], now, ids, import => import.AddSpaces());

    private SessionEdit ImportingReviewedSpaces(SessionState basis, ImportReviewedSpaces intent, DateTimeOffset now, IIdSource ids,
        bool previewed) =>
        Importing(basis, intent, intent.Spaces, previewed ? [] : intent.Reviews.Select(review => review.DestinationId).OfType<Guid>(),
            now, ids, import => import.ImportReviewed(intent.Reviews, ids));

    private SessionEdit ApplyingManualSetup(SessionState basis, ApplyManualSetup intent, DateTimeOffset now, IIdSource ids,
        bool previewed) =>
        Importing(basis, intent, intent.Spaces, previewed ? [] : intent.Drafts.Where(draft => !draft.IsNew).Select(draft => draft.SpaceId),
            now, ids, import => import.ApplyDrafts(intent.Drafts, intent.OrderWasEdited));

    /// An import's work: no Space among `destinations`, the ones it writes
    /// into, may be locked, and only the persistent workspace takes one. `apply` runs the
    /// intent's own rules over the Spaces read from `spaces`, then every
    /// record takes the identity sync needs and the issuing window shows what
    /// the import brought.
    private SessionEdit Importing(SessionState basis, ImportWorkspace intent, byte[] spaces, IEnumerable<Guid> destinations,
        DateTimeOffset now, IIdSource ids, Action<NativeWorkspaceImport> apply) {
        foreach (var id in destinations)
            if (basis.Spaces.FirstOrDefault(space => space.Id == id) is { } destination && IsLockedUnderGate(destination))
                throw new Rejected(new SpaceLocked(id));
        if (!workspaceKind.KeepsAppPreferences) throw new Rejected(new PersistentWorkspaceRequired(workspaceId));
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId));
        var import = new NativeWorkspaceImport(basis, spaces);
        apply(import);
        var result = import.Finish(now, ids, followUp);
        return new(result.Session, SyncStaging.Import, followUp,
            new SessionTabEvents(result.Copied, Favicon: null, Imported: result.Imported));
    }

    /// The session `intent` would leave, at `now`, and where the tabs it would
    /// place came from; nothing changes. It shows Spaces this process has not
    /// unlocked, as a person sees them before they import, and otherwise
    /// throws the `Rejected` that would refuse the import. Its new identities
    /// are drawn only for the answer.
    internal ImportedWorkspace Preview(ImportWorkspace intent, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(intent);
        lock (Gate) {
            var edit = Edit(intent, Stamp(now), new SystemIdSource(), pages: null, previewed: true)!;
            var events = edit.Events ?? SessionTabEvents.None;
            return new(edit.Next, events.Imported ?? [], [.. events.Copies.Select(copy => copy.Copied(workspaceId))]);
        }
    }

    /// The starting review for the imported Spaces `query` names, against this
    /// session's Spaces.
    internal SuggestedImportReview Answer(ImportReviewSuggestions query) {
        ArgumentNullException.ThrowIfNull(query);
        lock (Gate) return ImportReviewPolicy.Suggest(query.Sources, ReviewSpaces(), session.DisposableSeedMarker is not null);
    }

    /// What the reviews `query` names mean against this session's Spaces.
    /// Throws `Rejected` with `InvalidImport` when they do not pair with its
    /// sources.
    internal AnalyzedImportReview Answer(ImportReviewAnalysis query) {
        ArgumentNullException.ThrowIfNull(query);
        lock (Gate) return ImportReviewPolicy.Analyze(query.Sources, ReviewSpaces(), query.Reviews);
    }

    /// This session's Spaces as the review of an import reads them. The caller
    /// holds the gate.
    private ImportReviewSpace[] ReviewSpaces() => [.. session.Spaces.Select(space => new ImportReviewSpace(space.Id, space.Settings.Name,
        [.. space.Tabs.Select(tab => new ImportReviewTab(tab.Id, tab.Url, tab.Placement))]))];

    #endregion
}
