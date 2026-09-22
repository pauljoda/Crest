namespace CrestCore.Domain;

/// How a manual-setup draft presents one added tab in its placement.
public readonly record struct ManualSetupTab(string Title, string Symbol, bool KeepsSavedUrl);
