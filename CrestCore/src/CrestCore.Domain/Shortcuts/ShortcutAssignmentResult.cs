namespace CrestCore.Domain;

/// Whether a chord was bound, is already held by other commands, or can never
/// be a shortcut.
public enum ShortcutAssignmentResult { Assigned, Conflict, Invalid }
