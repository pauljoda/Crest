/// Decides which fractions a split starts a layout pass with.
///
/// Two callers need the same answer and must not disagree: the window model,
/// seeding its width transaction when the presented group changes, and the
/// columns view, which lays out every frame and cannot index a fraction list
/// that is one member behind the group it is drawing. A stored list whose
/// length no longer matches the group is not repaired here — a split of three
/// has no honest reading of two fractions — so it is discarded for equal
/// columns, the same starting point a brand-new group gets.
enum BrowserSplitLayoutSeedPolicy {
    static func fractions(persisted: [Double]?, memberCount: Int) -> [Double] {
        guard memberCount > 0 else { return [] }
        guard let persisted, persisted.count == memberCount else {
            return BrowserSplitColumnLayout.equalFractions(count: memberCount)
        }
        return BrowserSplitColumnLayout.normalizedFractions(persisted)
    }
}
