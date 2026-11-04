import AppKit

/// The last press of a Use Both shortcut that a focused page saw first, so the
/// shell can tell whether the page kept it. Both engines hand a press the page
/// lets go to the menu bar as the same event, and a press the page keeps never
/// comes back. A quick second press of the same keys then runs Crest's command
/// before the page sees it, and a press the page kept shows the window how.
@MainActor
final class BrowserMacPageKeptShortcut {
    // MARK: - Static Variables

    /// How long a press waits for the page to let it go before the window
    /// shows how to run the command. Both engines answer well inside it.
    private static let hintDelay: Duration = .milliseconds(250)
    /// How long after the first press a second press still runs the command,
    /// about as long as the hint stays up.
    private static let secondPressWindow: TimeInterval = 2

    // MARK: - Types

    /// One press of `shortcut` for `command`, the event's own timestamp, in
    /// the window it went to.
    private struct Press {
        let command: ShortcutCommand
        let shortcut: BrowserShortcut
        let timestamp: TimeInterval
        let windowNumber: Int
    }

    // MARK: - Variables

    private var press: Press?
    /// The hint showing for `press`, and the notices showing it.
    private var hint: (notice: BrowserNotice, notices: BrowserNotices)?
    /// A first press whose second press already ran the command, should the
    /// page let it go after all.
    private var answeredTimestamp: TimeInterval?

    // MARK: - Actions - Presses

    /// Whether `event` presses again the keys a page kept, so `command` runs
    /// now and the page never sees this press.
    func isSecondPress(_ event: NSEvent, of command: ShortcutCommand, shortcut: BrowserShortcut) -> Bool {
        guard let press, press.timestamp != event.timestamp, !event.isARepeat, press.command == command,
            press.shortcut == shortcut, press.windowNumber == event.windowNumber,
            event.timestamp - press.timestamp <= Self.secondPressWindow
        else { return false }
        answeredTimestamp = press.timestamp
        forget()
        return true
    }

    /// Remembers `event`, a press of `command`'s keys that the page sees
    /// first. If the page has not let it go once it has had time to, the
    /// window says how to run the command instead.
    func pageSees(_ event: NSEvent, of command: ShortcutCommand, shortcut: BrowserShortcut) {
        guard press?.timestamp != event.timestamp, !event.isARepeat else { return }
        forget()
        let pressed = Press(
            command: command, shortcut: shortcut, timestamp: event.timestamp, windowNumber: event.windowNumber)
        press = pressed
        Task { [weak self] in
            try? await Task.sleep(for: Self.hintDelay)
            guard let self, self.press?.timestamp == pressed.timestamp else { return }
            let notice = BrowserNotice.pressAgain(shortcut, for: command)
            if let notices = BrowserNoticeCenter.shared.post(notice) { self.hint = (notice, notices) }
        }
    }

    /// Answers whether the menu bar should drop `event`: the page let go of a
    /// press whose second press already ran the command. Any other press the
    /// page let go is forgotten, since the menu bar runs it now.
    func pageLetGo(_ event: NSEvent) -> Bool {
        if answeredTimestamp == event.timestamp {
            answeredTimestamp = nil
            return true
        }
        if press?.timestamp == event.timestamp { forget() }
        return false
    }

    /// Forgets the press, and puts away the hint it showed.
    private func forget() {
        press = nil
        if let hint { hint.notices.dismiss(hint.notice) }
        hint = nil
    }
}
