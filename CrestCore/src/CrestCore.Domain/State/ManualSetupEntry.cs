namespace CrestCore.Domain;

/// One Space of a reconciled draft. A draft index alone keeps that draft as
/// it is; with an existing index too, the draft refreshes its existing-Space
/// facts from that Space; an existing index alone adds a draft for a Space
/// created elsewhere while setup was open.
public readonly record struct ManualSetupEntry(int? DraftIndex, int? ExistingIndex);
