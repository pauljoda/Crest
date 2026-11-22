import Foundation

/// The order setup walks its steps in: Bring Tabs first; then, when another
/// browser brings Spaces in, the Spaces to look over; or else the person's
/// first Space, made here, and then any more; and last, the choices that
/// make Crest home: the default browser, the search and ad blocking.
/// Continue leads to the next
/// step's page, Back to the one before it, and a page deeper in a step back
/// to the step's own page.
struct BrowserSetupWalk: Equatable {
    // MARK: - Variables

    /// Whether another browser brings Spaces in.
    let imports: Bool

    /// The steps in order.
    var steps: [BrowserSetupStep] {
        imports ? [.bring, .spaces, .home] : [.bring, .yourSpace, .spaces, .home]
    }

    // MARK: - Functions

    /// The page Continue leads to from `destination`, or nil from the last
    /// step, which starts Crest.
    func page(after destination: BrowserSetupDestination) -> BrowserSetupDestination? {
        guard let index = position(of: destination.step), index + 1 < steps.count else { return nil }
        return page(of: steps[index + 1])
    }

    /// The page Back leads to from `destination`: its step's own page from a
    /// page deeper in the step, else the step before, or nil for the welcome.
    func page(before destination: BrowserSetupDestination) -> BrowserSetupDestination? {
        if let stepPage = destination.stepPage { return stepPage }
        guard let index = position(of: destination.step), index > 0 else { return nil }
        return page(of: steps[index - 1])
    }

    /// The page a step's chip opens: the step's own page, or nil for a step
    /// the walk skips.
    func page(opening step: BrowserSetupStep) -> BrowserSetupDestination? {
        steps.contains(step) ? page(of: step) : nil
    }

    /// Whether opening `step` from `destination` goes back toward the
    /// welcome.
    func goesBack(to step: BrowserSetupStep, from destination: BrowserSetupDestination?) -> Bool {
        guard let destination, let target = position(of: step), let current = position(of: destination.step)
        else { return false }
        return target < current
    }

    /// Whether `destination` belongs to the last step, whose Continue starts
    /// Crest.
    func isLast(_ destination: BrowserSetupDestination) -> Bool {
        destination.stepPage == nil && page(after: destination) == nil
    }

    // MARK: - Actions - Reading

    /// Where `step` stands in the walk; a step the walk skips stands where
    /// the step it gives way to does.
    private func position(of step: BrowserSetupStep) -> Int? {
        steps.firstIndex(of: step) ?? (step == .yourSpace ? steps.firstIndex(of: .spaces) : nil)
    }

    private func page(of step: BrowserSetupStep) -> BrowserSetupDestination? {
        BrowserSetupDestination.stepPages.first { $0.step == step }
    }
}
