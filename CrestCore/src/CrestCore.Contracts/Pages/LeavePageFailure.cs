namespace CrestCore.Contracts;

/// The person left the notice of a page's failed navigation for the page
/// behind it. Refused when the page is not open.
public sealed record LeavePageFailure(Guid PageId) : PageIntent;
