/// Counts consecutive renderer terminations for one page. The reload budget
/// itself belongs to the core, so every engine gives up at the same point.
struct BrowserProcessRecovery {
    private(set) var consecutiveTerminations = 0

    mutating func recordTermination() -> BrowserProcessRecoveryAction {
        consecutiveTerminations += 1
        return BrowserCorePolicy.processRecoveryAction(
            consecutiveTerminations: consecutiveTerminations
        )
    }

    mutating func recordSuccessfulNavigation() {
        reset()
    }

    mutating func reset() {
        consecutiveTerminations = 0
    }
}
