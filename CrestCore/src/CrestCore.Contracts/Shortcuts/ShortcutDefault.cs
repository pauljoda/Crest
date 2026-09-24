namespace CrestCore.Contracts;

/// A command's default key combination on one platform. A default that
/// `YieldsToOverrides` stays unbound while the person has given its keys to
/// another command, so a default added after people could customize never
/// takes keys they already chose; resetting that command restores it.
public sealed record ShortcutDefault(DevicePlatform Platform, KeyCombination Keys, bool YieldsToOverrides);
