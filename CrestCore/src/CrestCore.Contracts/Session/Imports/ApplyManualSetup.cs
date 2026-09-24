namespace CrestCore.Contracts;

/// Applies a manual setup: each Space of `Spaces` is a draft, and `Drafts`
/// says for each whether it makes a new Space or adds to the existing Space
/// with its identity and profile, and the name and look that Space takes. A
/// draft's tabs join each section after the tabs the Space already holds
/// there. When `OrderWasEdited`, the Spaces take the drafts' order, followed by
/// any Space the drafts do not name. A first launch's Spaces stop being
/// disposable.
///
/// Refused with `PinnedTabsFull` when a Space would pin too many tabs,
/// `SpaceProfileChanged` when an existing Space no longer uses the draft's
/// profile, and `SpaceAlreadyExists` or `ProfileInUse` when a new Space takes
/// an identity or profile another Space holds.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ApplyManualSetup(Guid WorkspaceId, Guid WindowId, byte[] Spaces, IReadOnlyList<SetupSpace> Drafts,
    bool OrderWasEdited) : ImportWorkspace(WorkspaceId, WindowId);
