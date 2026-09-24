namespace CrestCore.Contracts;

/// Why a page's navigation to `Url` failed. `Error` names the problem the same
/// way whichever engine saw it, and is what behavior that differs by failure
/// reads. `ReplacedDocument` says the failure took the place of the document
/// the page showed, as an engine's committed error page does; otherwise the
/// page still shows that document behind the failure, and leaving the failure
/// returns to it. `Domain` and `Code` are the engine's own error, which the
/// failure page shows as technical details and nothing branches on.
public sealed record PageFailure(NavigationError Error, string? Url, bool ReplacedDocument, string Domain, long Code);
