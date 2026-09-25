namespace CrestCore.Contracts;

/// Shows the page at `Factor` times its size, from 0.25 to 5. A page still
/// being created takes the factor once it exists.
public sealed record ZoomPage(Guid PageId, double Factor) : PageRequest<bool>;
