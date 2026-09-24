namespace CrestCore.Contracts;

/// Whether an intent would be accepted: `Refusal` names the rule that would
/// refuse it, or is null when the core would accept it.
public sealed record SendPermission(Rejection? Refusal);
