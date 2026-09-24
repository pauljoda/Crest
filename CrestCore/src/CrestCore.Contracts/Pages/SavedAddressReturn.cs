namespace CrestCore.Contracts;

/// Whether returning a tab to its saved address would take it or its page
/// somewhere else.
public sealed record SavedAddressReturn(bool ChangesPage);
