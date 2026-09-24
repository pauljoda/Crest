namespace CrestCore.Contracts;

/// Whether the core would accept a session intent now, and when it would not,
/// the rule that would refuse it. Nothing changes, so a menu can ask the
/// core's own rules, such as a folder's depth or a split's size, before it
/// offers an action.
public sealed record CanSend(Intent Intent) : Query<SendPermission>;
