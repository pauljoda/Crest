import Observation

/// The element picker of one page, as its bar shows it: whether it runs, what
/// the person picked, and whether the pick can grow to the element around it
/// or shrink back to the one inside. The page's cosmetic bridge reports it, and
/// the bar's commands go back to the bridge.
@MainActor
@Observable
final class BrowserElementPicker {
    // MARK: - Types

    /// A command the bar gives the picker, by the bridge's name for it.
    enum Command: String {
        case wider
        case narrower
        case block
        case cancel
    }

    // MARK: - Variables

    private(set) var isActive = false
    /// The selector of what the person picked, which blocking it keeps; nil
    /// until they pick.
    private(set) var selector: String?
    private(set) var canWiden = false
    private(set) var canNarrow = false
    /// Gives the page's bridge a command; the page's cosmetic session sets it.
    @ObservationIgnored var send: ((Command) -> Void)?

    // MARK: - Actions - Commands

    func widen() { send?(.wider) }

    func narrow() { send?(.narrower) }

    func block() { send?(.block) }

    /// Stops picking at once; the bridge confirms as it closes.
    func cancel() {
        send?(.cancel)
        end()
    }

    // MARK: - Mutators

    /// What the bridge reports, `report`, read once here.
    func apply(_ report: [String: Any]) {
        guard report["active"] as? Bool == true else { return end() }
        isActive = true
        selector = report["selector"] as? String
        canWiden = report["canWiden"] as? Bool == true
        canNarrow = report["canNarrow"] as? Bool == true
    }

    /// The picker stopped, or its document went away.
    func end() {
        isActive = false
        selector = nil
        canWiden = false
        canNarrow = false
    }
}
