using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// This device's shortcut choices, which the device store keeps. What a
/// choice binds is read on the device's platform, over the commands its
/// default engine offers.
internal sealed partial class Device {
    #region Variables

    private ShortcutOverrides shortcuts = ShortcutOverrides.None;

    #endregion

    #region Actions - Shortcut intents

    /// Runs one shortcut intent over `offered`, the commands this device
    /// offers, publishing the bindings when any of them changed.
    public void Handle(ShortcutIntent intent, IReadOnlyList<ShortcutCommand> offered, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(offered);
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) {
            if (intent is AdoptShortcuts adoption) {
                Adopt(adoption);
                changes.Publish(Shortcuts(offered));
                return;
            }
            var revised = intent switch {
                AssignShortcut assigning => shortcuts.Assigning(assigning.Command, Chord(assigning.Keys), offered, platform),
                ReassignShortcut reassigning => shortcuts.Reassigning(reassigning.Command, Chord(reassigning.Keys), offered, platform),
                UnassignShortcut unassigning => shortcuts.Unassigning(unassigning.Command, platform),
                ResetShortcut resetting => shortcuts.Resetting(resetting.Command),
                ResetShortcuts => ShortcutOverrides.None,
                _ => throw new ArgumentOutOfRangeException(nameof(intent), intent.GetType().Name, "The device does not handle this intent.")
            };
            if (revised.SameAs(shortcuts)) return;
            var before = Shortcuts(offered);
            shortcuts = revised;
            storage?.EnqueueDevice(Records());
            var after = Shortcuts(offered);
            if (after.IsCustomized != before.IsCustomized || !after.Bindings.SequenceEqual(before.Bindings)) changes.Publish(after);
        }
    }

    /// Carries the choices an installed release kept into the device store
    /// once, after any the store already holds, and saves them before
    /// returning. The caller holds the device lock.
    private void Adopt(AdoptShortcuts intent) {
        if (storage is not { } target || adopted.Contains(DeviceAdoption.Shortcuts)) return;
        var merged = ShortcutOverrides.Restore([.. shortcuts.Chords, .. LegacyShortcutDocument.Read(intent.Overrides)]);
        var carried = Records().Adopting(DeviceAdoption.Shortcuts) with { Shortcuts = merged };
        try {
            target.SaveDevice(carried);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
        shortcuts = merged;
        adopted.Add(DeviceAdoption.Shortcuts);
        // Records handed to the store before this carry nothing adopted; these supersede them.
        target.EnqueueDevice(Records());
    }

    /// The bindings over `offered` when the commands this device offers
    /// changed from `before`, or null when no binding differs.
    public ShortcutsChanged? ShortcutsAfter(IReadOnlyList<ShortcutCommand> before, IReadOnlyList<ShortcutCommand> offered) {
        lock (gate) {
            var previous = Shortcuts(before);
            var next = Shortcuts(offered);
            return next.Bindings.SequenceEqual(previous.Bindings) ? null : next;
        }
    }

    /// Every offered command's binding. The caller holds the device lock.
    private ShortcutsChanged Shortcuts(IReadOnlyList<ShortcutCommand> offered) =>
        new(shortcuts.Bindings(offered, platform), shortcuts.IsCustomized);

    /// The chord `keys` spell, or `InvalidShortcut` for keys that can never be one.
    private static ShortcutChord Chord(KeyCombination keys) =>
        ShortcutChord.Usable(keys) ?? throw new Rejected(new InvalidShortcut(keys));

    #endregion
}
