namespace CrestCore.Contracts;

/// What a new tab shows: the page at `Address`, the native view `View`, or,
/// with neither, the Start Page. `Title` names a page until it loads and
/// reports its own; a page without one is titled by its host.
///
/// A native view's `Title` and `Symbol` are TRANSITIONAL: the platform gives
/// them until native view kinds become a fixed set that carries its own
/// localized title and symbol.
public sealed record TabContent(string? Address, NativeTabContent? View, string? Title, string? Symbol);
