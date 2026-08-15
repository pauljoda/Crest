struct BrowserProcessRecovery {
    private(set) var consecutiveTerminations = 0
    let maximumAutomaticReloads: Int

    init(maximumAutomaticReloads: Int = 2) {
        self.maximumAutomaticReloads = maximumAutomaticReloads
    }

    mutating func recordTermination() -> BrowserProcessRecoveryAction {
        consecutiveTerminations += 1
        return consecutiveTerminations <= maximumAutomaticReloads ? .reload : .showFailure
    }

    mutating func recordSuccessfulNavigation() {
        reset()
    }

    mutating func reset() {
        consecutiveTerminations = 0
    }
}
