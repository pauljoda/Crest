namespace CrestCore.Domain;

/// One off-screen page candidate as the native store sees it. `InactiveSince`
/// is the idle stamp in seconds; a candidate without one (a native engine tab
/// holding no Crest page) sorts after every stamped candidate.
public sealed record ResidencyCandidate(string TabId, double? InactiveSince, bool KeepsPageLoaded,
    bool IsPresented, int? PresentedIndex);
