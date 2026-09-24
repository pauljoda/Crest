namespace CrestCore.Contracts;

/// The modifier keys held with a shortcut's key. The values are the bits of
/// the native modifier mask that persisted shortcuts store.
[Flags]
public enum ShortcutModifiers {
    None = 0,
    Command = 1 << 0,
    Option = 1 << 1,
    Control = 1 << 2,
    Shift = 1 << 3
}
