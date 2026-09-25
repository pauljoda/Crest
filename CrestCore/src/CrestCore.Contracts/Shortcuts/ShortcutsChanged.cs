namespace CrestCore.Contracts;

/// The chord each offered command answers to changed. `Bindings` covers every
/// offered command in catalog order; `IsCustomized` says whether the person
/// changed any shortcut, including one this device does not offer.
public sealed record ShortcutsChanged(IReadOnlyList<ShortcutBinding> Bindings, bool IsCustomized) : Change;
