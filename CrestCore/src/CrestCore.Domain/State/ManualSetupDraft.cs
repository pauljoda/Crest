namespace CrestCore.Domain;

/// One Space in a manual-setup draft: an existing Space it edits, or a new one.
public readonly record struct ManualSetupDraft(Guid Id, bool IsNew);
