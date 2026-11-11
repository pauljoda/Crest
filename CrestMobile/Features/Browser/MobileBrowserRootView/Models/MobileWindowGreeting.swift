import Foundation
import Observation

/// How a window greets the person by itself: once as it launches, with the
/// new tab or the search its startup choice asks for, and with search again
/// when they come back after a while in the background, still on the tab
/// they left. The window keeps it for as long as it lives, so the browser it
/// shows again after private browsing never greets them a second time.
///
/// A link another app hands the window is what the person came for, so it
/// claims the window before it is routed: a greeting still to come stays
/// away, and search already up goes.
@Observable
@MainActor
final class MobileWindowGreeting {
    // MARK: - Static Variables

    /// How long a window stays in the background before search greets the
    /// person coming back to it.
    static let awayInterval: TimeInterval = 5 * 60

    // MARK: - Variables

    /// How many links other apps handed the window, each of which puts away
    /// search that is up.
    private(set) var externalLinkCount = 0

    /// Whether the launch has yet to greet the person.
    @ObservationIgnored private var awaitsLaunch = true
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var leftTabID: UUID?

    // MARK: - Actions - Launch

    /// Whether the launch greets the person now: true the first time the
    /// window's browser asks, unless a link claimed the window first.
    func takeLaunch() -> Bool {
        defer { awaitsLaunch = false }
        return awaitsLaunch
    }

    // MARK: - Actions - Return

    /// Notes the window going into the background, showing `tabID`.
    func leave(showing tabID: UUID?, at date: Date = .now) {
        leftAt = date
        leftTabID = tabID
    }

    /// Whether search greets the person coming back at `date` to a window
    /// showing `tabID`: they were away long enough, the window still shows
    /// the tab they left, and no link brought them back. Each return answers
    /// once.
    func comesBack(showing tabID: UUID?, at date: Date = .now) -> Bool {
        defer {
            leftAt = nil
            leftTabID = nil
        }
        guard let leftAt, date.timeIntervalSince(leftAt) >= Self.awayInterval else { return false }
        return tabID == leftTabID
    }

    // MARK: - Actions - Links

    /// A link another app handed the window, before it is routed: neither
    /// the launch nor the return it brought the person back on greets them,
    /// and search already up goes.
    func yieldToExternalLink() {
        awaitsLaunch = false
        leftAt = nil
        leftTabID = nil
        externalLinkCount &+= 1
    }
}
