namespace CrestCore.Contracts;

/// Imports the Spaces of `Spaces` a person reviewed, as `Reviews` choose, one
/// review for each of them. An included Space becomes a new Space or joins the
/// existing one its review names, taking the name and look the review gives
/// it, with the tabs the review includes in the placements it chose and the
/// saved folders those tabs need; a folder matches one the destination holds
/// by title. Pinned tabs past a destination's limit become saved tabs in an
/// `Imported Pinned Tabs` folder. A new Space keeps its archive and history.
/// Over a first launch's disposable Spaces, the reviewed Spaces replace them.
///
/// Refused with `NoIncludedSpaces` when the review includes none.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ImportReviewedSpaces(Guid WorkspaceId, Guid WindowId, byte[] Spaces, IReadOnlyList<SpaceReview> Reviews)
    : ImportWorkspace(WorkspaceId, WindowId);
