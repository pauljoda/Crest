namespace CrestCore.Domain;

/// One command's live chord, its catalog default and whether the person has
/// overridden it. A null `Shortcut` leaves the command without a chord.
public sealed record ShortcutBinding(string Command, ShortcutChord? Shortcut, ShortcutChord? Default, bool IsCustomized);
