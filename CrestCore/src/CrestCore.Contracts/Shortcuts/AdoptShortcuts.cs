namespace CrestCore.Contracts;

/// Carries the shortcut choices an installed release kept in its defaults
/// into the device store, once, and publishes every offered command's chord.
/// `Overrides` is the document that release saved under
/// `crest.keyboard-shortcuts.v1`, or null when it saved none. An entry this
/// build cannot read is left out; one for a command it does not know is kept.
/// The store is written before the intent returns; a device that adopted them
/// before, or keeps no file, adopts nothing and still publishes its bindings.
public sealed record AdoptShortcuts(byte[]? Overrides) : ShortcutIntent;
