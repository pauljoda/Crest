using CrestCore.Application;

namespace CrestCore.Contracts;

/// Makes `Preference` answer `Command`'s keys while a focused page uses them
/// too. A command reserved from pages keeps its own, and nothing changes.
public sealed record ChooseShortcutPreference(ShortcutCommand Command, ShortcutPreference Preference) : ShortcutIntent {
    #region Actions - Device

    internal override void Apply(Device device, ShortcutTurn turn) =>
        device.ReviseShortcuts(turn, shortcuts => shortcuts.Preferring(Command, Preference));

    #endregion
}
