namespace CrestCore.Contracts;

/// Another custom engine in the Space already uses this name, ignoring case and
/// diacritics.
public sealed record DuplicateSearchEngineName() : Rejection;
